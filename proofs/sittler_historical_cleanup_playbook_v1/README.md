# Sittler historical cleanup playbook (v1)

Goal: safely quantify + eliminate *historical* review-queue pollution caused by the **Sittler staff-name leak**, and verify **no new post-deploy leaks**.

Scope (per STRAT directive): **no prod writes in this playbook**. Read-only queries are runnable via `scripts/query.sh`; the cleanup SQL is provided as a **proposal only** (not executed).

## Cutover

Blocklist enforcement for Sittler deployed **2026-02-15 19:43 UTC**. All audit/proof queries below bucket relative to that cutover.

## 1) Audit (read-only)

Counts of any Sittler attributions by day, split by decision (`assign`/`review`/`none`) and pre/post cutover:

- Run: `scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/audit_sittler_attributions_by_day.sql`
- Expected: **post_cutover = 0** rows (or zero counts).

## 2) Proof (read-only)

Sample any *post-cutover* Sittler attributions (should be none). Includes debug fields for root-cause if nonzero (`prompt_version`, `model_id`, `attributed_by`, `attribution_lock`, `segmenter_version`, `segment_generation`):

- Run: `scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/proof_post_cutover_sittler_attributions_sample.sql`
- Expected: **0 rows** returned.

## 3) Historical review-queue pollution (read-only + proposal)

### 3a) Target selection (read-only)

Select pending historical `review_queue` items whose **latest** router output predicts a Sittler project (and is *not applied*), excluding any spans with a `human` lock:

- Run: `scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/targets_historical_review_queue_sittler.sql`

### 3b) Cleanup proposal (NOT executed)

Reversible SQL to bulk-dismiss those historical items (writes a backup table first, instructs export, then updates `review_queue`).

- File: `proofs/sittler_historical_cleanup_playbook_v1/sql/cleanup_proposal_dismiss_historical_review_queue_sittler.sql`
- **Do not run** without STRAT approval + a controlled psql session (this will be rejected by `scripts/query.sh` because it mutates).

## Coordination / non-overlap

This playbook is **only** for Sittler/staff-name-leak artifacts. It intentionally does **not** overlap with DEV-2 “junk call prefilter” work.

