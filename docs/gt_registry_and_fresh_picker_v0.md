# GT Registry + “Fresh Candidate Picker” — Spec v0

**Owner:** DATA-3  
**Date:** 2026-02-16  
**Status:** Draft (design-first; no prod schema changes)  
**Goal:** Prevent re-labeling the same calls/spans while expanding GT coverage from the live review queue.

---

## 1) Problem

Chad needs rerunnable GT batches for regression loops. Without a registry + dup-detect, we keep picking the same review items and paying the labeling cost repeatedly.

We need a minimal, deterministic way to:
- record what has already been labeled (or reserved for labeling),
- pick fresh candidates from `public.v_review_queue_spans`,
- and keep the process safe for parallel agent sessions (FOR_SESSION routing).

---

## 2) Definitions

- **GT label:** human ground truth for a span (project assignment or `none`).
- **Fixture:** a unit we can re-run (typically `interaction_id` + a set of spans).
- **Manifest:** a CSV listing fixtures/spans to label (or already labeled), with light metadata.
- **Registry:** the dedupe memory; a canonical list of fixtures/spans that are already labeled or reserved.

---

## 3) Unique Key (what counts as “the same GT item”)

We need two levels:

### 3.1 Call-level fixture key (minimum viable)

**Key:** `interaction_id`

This is stable across reseeds and span-id churn. It prevents the biggest failure mode: re-labeling the same call.

### 3.2 Span-level fixture key (preferred when available)

Span IDs are **not stable** across `admin-reseed` (it supersedes spans and inserts new ones, incrementing `segment_generation`), so `(interaction_id, span_id)` is not sufficient.

**Recommended span identity for dedupe:**
- `interaction_id`
- `span_index`
- `span_text_hash` (hash of the full span transcript text; detects segmentation-boundary changes)
- optional: `transcript_variant` if/when we support multiple transcript variants

This makes reseed idempotent *when span text is identical*, and treats genuinely different segmentation as a new labeling target.

---

## 4) Registry Storage Options (v0 recommendation)

### Option A — Repo CSV/JSONL registry (recommended for v0)

Authoritative sources:
- Existing labeled spans live in `proofs/gt/inputs/**/GT_LABELING.csv` (already in repo).
- Each “manifest” we generate is a second dedupe source (reserved-but-unlabeled fixtures).

Proposed tracked paths:
- `proofs/gt/inputs/<YYYY-MM-DD>/GT_LABELING.csv` (labels)
- `proofs/gt/manifests/gt_manifest_v*.csv` (reservations / labeling worklists)

Optionally add a derived registry file:
- `proofs/gt/registry/gt_registry_v0.jsonl` (append-only; generated from labels + manifests)

Pros:
- No schema changes.
- Easy to code review and reproduce.
- Works offline; no DB write permissions needed.

Cons:
- Merge conflicts possible if multiple sessions write the same registry/manifest simultaneously.
- Requires discipline: single-writer per artifact (enforced via TRAM FOR_SESSION + receipts).

### Option B — Supabase table (future; not for v0 unless STRAT-2 requests)

Candidates:
- `ground_truth_segments` (already exists but historically unused)
- or a new `gt_registry` table

Pros:
- Strong concurrency and queryability.
- Natural for automation / UI.

Cons:
- Schema + migration overhead; not required for next proof loop.

---

## 5) Fresh Candidate Picker (algorithm)

Input:
- `public.v_review_queue_spans` (pending/open review items)
- dedupe set from:
  - all `call_id` values in `proofs/gt/inputs/**/GT_LABELING.csv`
  - all `interaction_id` values in `proofs/gt/manifests/gt_manifest_v*.csv`

Steps:
1. Query pending review spans (limit a few thousand).
2. Group by `interaction_id`, collecting:
   - span indices present
   - min/avg confidence
   - reason codes
   - contact identity (join to `public.interactions` by `interaction_id`)
   - predicted project (best-effort from latest attribution)
3. Filter out any `interaction_id` already in dedupe set.
4. Choose 10–15 interaction_ids to maximize diversity:
   - multi-span calls (likely topic switches)
   - floater/internal contacts (e.g., Zack Sittler, Randy Booth)
   - low-confidence spans (<0.75)
   - at least one voicemail/non-attributable case
   - at least two projects represented (best-effort)
5. Emit `gt_manifest_v2.csv` with one row per span to label, leaving GT fields blank.

Output contract:
- CSV header matches `gt_manifest_v1.csv` (see §6).
- Store under `proofs/gt/inputs/<YYYY-MM-DD>/gt_manifest_v2.csv` **or** `proofs/gt/manifests/gt_manifest_v2.csv` (pick one; avoid `artifacts/` since it is gitignored).

---

## 6) Manifest Format (v0)

Use the exact header used by `gt_manifest_v1.csv`:

`interaction_id,span_index,expected_project,expected_decision,anchor_quote,bucket_tags,notes,labeled_by,labeled_at_utc`

For fresh/unlabeled candidates:
- `expected_project` = empty
- `expected_decision` = empty
- `labeled_by` / `labeled_at_utc` = empty
- `anchor_quote` = short excerpt of the span transcript (or transcript_snippet)
- `bucket_tags` = semicolon-delimited tags (e.g., `bucket:low_confidence;bucket:floater_contact`)
- `notes` = why selected / any caution

---

## 7) “Consumed” Semantics (how we prevent duplicates)

v0 rule:
- Once an `interaction_id` appears in any committed `gt_manifest_v*.csv`, it is treated as **consumed/reserved**, even if not yet labeled.
- Once labeled, it also appears in `GT_LABELING.csv` and becomes permanently excluded from “fresh” picking.

This is intentionally conservative to stop repeat work.

---

## 8) Integration Notes

- **GT runner (PR #95):** `scripts/gt_batch_runner.py` expects a different input shape (`gt_batch_v1.csv`). A follow-up script can map `gt_manifest_v*.csv` + labeled GT into runner inputs by adding `expected_project_id` via a project-key→UUID map.
- **GT run report template (PR #97):** manifests + registry provide the stable “what was evaluated” inventory referenced in the report.

---

## 9) Guardrails (collaboration)

- All changes to manifests/registry must be routed via TRAM with `FOR_SESSION` ownership (single-writer).
- Never modify existing labeled rows; append new manifests or new label files by date.
- Do not involve DATA-1 (protected for self-scoring).

