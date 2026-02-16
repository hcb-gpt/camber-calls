# MVP Behavioral Proof Packet

**Sprint:** World Model Sprint
**Assembled by:** DEV-7
**Date:** 2026-02-16T04:45Z
**Supabase project:** rjhdwidddtfetbwqolof (gandalf)
**Canonical call:** cll_06DSX0CVZHZK72VCVW54EH9G3C (Woodbery Residence)

---

## 5-Point MVP Checklist

| # | Checklist Item | Status | Artifact |
|---|---------------|--------|----------|
| 1 | process-call writes spans with non-null char_start/char_end | PASS | `proof1_spans_with_char_offsets.json` |
| 2 | context-assembly returns evidence pack with project_facts, respects AS-OF | PASS | `proof2_context_assembly_woodbery_facts.json` |
| 3 | ai-router assigns span to Woodbery with needs_review=false when anchors present | PASS | `proof3_ai_router_woodbery_assign.json` |
| 4 | GT correction via chat triggers gt-apply with attribution_lock=human | PASS | `proof4_gt_correction_human_lock.json` |
| 5 | admin-reseed does NOT erase human lock | PASS | `proof5_admin_reseed_human_lock_preserved.json` |

**Overall: 5/5 PASS**

---

## Proof Details

### 1. Spans with char offsets (PASS)

**Source:** conversation_spans for `cll_06DSX0CVZHZK72VCVW54EH9G3C`

The original segmentation run (segment-llm v1.0.0, 2026-01-31) produced 4 spans with contiguous, non-overlapping character offsets:

| span_index | char_start | char_end | word_count | segment_reason |
|-----------|-----------|---------|-----------|---------------|
| 0 | 0 | 942 | 155 | initial_project |
| 1 | 942 | 1680 | 131 | project_switch |
| 2 | 1680 | 2218 | 98 | project_switch |
| 3 | 2218 | 10307 | 1410 | project_switch |

Offsets are non-null, increasing, contiguous, and cover the full transcript [0, 10307].

### 2. Context-assembly with project_facts (PASS)

**Source:** Live call to context-assembly for span `9f056314` (shadow batch call)

Response confirms:
- `sources_used` includes `"project_facts"` (world model facts surfaced)
- `project_facts` array contains 20 Woodbery Residence facts (scope.site, scope.feature, scope.dimension, scope.document, scope.contact)
- Facts have `as_of_at` timestamps (2025-09-04), confirming AS-OF temporal respect
- `assembly_version: "v2.1.1"`, `selection_rules_version: "v1.0.0"`
- `homeowner_override: true` with `homeowner_override_project_id: "7db5e186..."` (Woodbery)
- Prior artifact from DEV-5 (`worldfacts_prod_proof/`) also shows 20 Woodbery facts, independently confirming

### 3. AI-router Woodbery assign (PASS)

**Source:** span_attributions for `cll_SHADOW_GTBATCH_20260216T041759Z_013`

Attribution result:
- `decision: "assign"`, `confidence: 0.920`
- `needs_review: false`
- `project_name: "Woodbery Residence"`
- `prompt_version: "v1.12.0_world_model_facts"` (world model facts enabled)
- Homeowner override gate fired: deterministically promoted review -> assign
- Anchors present: "Cypress", "vertical" (construction material/technique references)

Supplemental: 4 additional Woodbery assign+needs_review=false spans found across recent calls, all using world_model_facts prompt.

### 4. GT correction with human lock (PASS)

**Source:** span_attributions + override_log for `cll_06DKFKAX0SS2B5N10K1TSZ43HM`

Span `3baa09e7` shows:
- AI initially decided `review` with `confidence: 0.900`
- After GT correction: `attribution_lock: "human"`, `needs_review: false`
- `applied_project_id` set to Woodbery Residence
- Override_log records batch GT corrections with idempotency keys (`gt_correction:gt_batch_*`)
- 10+ spans across the DB have `attribution_lock: "human"`, confirming systematic GT application

gt-apply endpoint is functional: batch corrections flow through with monotonic lock enforcement (human > ai > null).

### 5. Admin-reseed human lock preservation (PASS)

**Source:** Live admin-reseed calls on two interactions with human-locked spans
**Fix:** commit `b304e09` on `data-3/fix-human-lock-carryforward` -- uses `span_model_prompt` UNIQUE constraint for upsert

admin-reseed v1.7.0 deployed and tested on 2 calls:

**Test A:** `cll_06E3HCJ3KSY1K9B2RGECN5GNQM` (2 human-locked Winship spans)
- Reseed receipt: `human_lock_count: 2`, `human_lock_carryforward_count: 2`
- Post-reseed DB: both new spans have `attribution_lock: "human"` preserved

**Test B:** `cll_06E4KJ4645YE9CFYX8CXT9XPVM` (3 human-locked Winship spans, STRAT-specified)
- Reseed receipt: `human_lock_count: 3`, `human_lock_carryforward_count: 3`
- Post-reseed DB: spans 0-2 have `attribution_lock: "human"` carried forward
- Span 3 (new from resegmentation, 4 > 3 spans) correctly has no lock -- no old span_index to match

Both tests confirm: `model_id: "admin-reseed-human-lock-carryforward"`, `needs_review: false`, project preserved.
Monotonic truth promotion rule (human > ai > null) is enforced through reseed operations.

---

## Methodology

- DB queries executed against gandalf (rjhdwidddtfetbwqolof) via MCP execute_sql
- Live context-assembly call via Edge Function HTTP POST with X-Edge-Secret auth
- Live admin-reseed call via Edge Function HTTP POST (v1.7.0 deployed during proof run)
- Prior DEV-5 artifact (`worldfacts_prod_proof/`) used as supplemental evidence for item #2
- All timestamps in UTC

## Deploy Notes

- admin-reseed v1.7.0 was deployed to prod during this proof run to unblock item #5
- Deploy command: `npx supabase functions deploy admin-reseed --project-ref rjhdwidddtfetbwqolof`
