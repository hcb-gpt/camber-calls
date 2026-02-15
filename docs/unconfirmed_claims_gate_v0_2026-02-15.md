# Unconfirmed Claims Gate v0 (Contamination Control)

## Objective
Prevent unconfirmed claim outputs from becoming reusable system truth. Specifically: claims derived from `review`/`none`/`model_error` attribution lanes must not be consumed by retrieval/crossref/consolidation until confirmed.

## Problem Statement
Current read paths primarily filter `journal_claims.active = true`, which allows unconfirmed rows into reuse paths:
- `context-assembly` claim overlap + cross-contact claim match + journal state pulls active claims without confirmation filter.
- `journal-consolidate` builds "existing knowledge base" from active claims without confirmation filter.
- `xref_search_journal_claims` RPC filters `active=true` + embedding, but not confirmation state.

Observed live distribution (2026-02-15 UTC):
- active `journal_claims` by `attribution_decision`: `review=3031`, `<null>=1491`, `assign=588`.
- active embedded claims (semantic xref input): `review=393`, `<null>=302`, `assign=17`.

This means most retrievable semantic memory currently comes from unconfirmed lanes.

## Guardrail Policy (v0)
Define confirmation state at claim level:
- `confirmed`: `attribution_decision='assign'` AND `claim_project_id IS NOT NULL`.
- `unconfirmed`: anything else (`review`, `none`, `model_error`, `NULL`, missing project assignment).

Rule:
- Retrieval/consolidation inputs must use `confirmed` only.
- Unconfirmed claims stay stored for audit/debug/review, but are excluded from reusable context.

## Proposed Schema (minimal path)
Add columns to `public.journal_claims`:
- `claim_confirmation_state text NOT NULL DEFAULT 'unconfirmed'` with check in (`confirmed`,`unconfirmed`).
- `confirmed_at timestamptz NULL`.
- `confirmed_by text NULL` (`auto_assign`,`review_resolve`,`backfill_v0`, etc.).

Backfill once:
- `confirmed` where active and `attribution_decision='assign'` and `claim_project_id IS NOT NULL`.
- otherwise `unconfirmed`.

## Read-Path Enforcement Points
1. `supabase/functions/context-assembly/index.ts`
- Source 8 (`journal_claims` overlap), Source 10 (cross-contact), Source 12 (journal state).
- Add `.eq("claim_confirmation_state", "confirmed")`.

2. `supabase/functions/journal-consolidate/index.ts`
- `existingClaims` context must include confirmed claims only.
- Keep `newClaims` processing unchanged; only the reusable baseline gets filtered.

3. `supabase/migrations/*xref_search_journal_claims*.sql`
- Add `AND jc.claim_confirmation_state = 'confirmed'` in RPC.

4. Optional defense-in-depth
- Add `public.v_confirmed_journal_claims` view and switch read paths to view to reduce drift.

## Write-Path Updates
1. `journal-extract`
- Persist `attribution_decision` from latest `span_attributions.decision`.
- Set `claim_confirmation_state` at insert time (`assign` => confirmed; else unconfirmed).

2. `review-resolve`
- On human resolve/apply project, update related claim rows to `confirmed`, set `confirmed_at`, `confirmed_by='review_resolve'`.

3. `admin-reseed` / reroute follow-ups
- Any claim re-attribution path that reaches deterministic/human assignment should flip to `confirmed`.

## Rollout Plan
Phase 1: schema + backfill + dual-read metric (old vs confirmed-only counts).
Phase 2: enable confirmed-only filters in context-assembly + xref RPC behind feature flag.
Phase 3: enforce in journal-consolidate and remove fallback.

## Success Criteria
- 0 confirmed-path queries returning `unconfirmed` rows.
- measurable drop in cross-project contamination incidents tied to review/null lanes.
- no regression on known GT assignment proofs after gate enablement.

## DATA Feasibility Questions
Sent request: `request__data_schema_feasibility__unconfirmed_claims_gate_v0`.
Need DATA decision on:
- single-column state vs event-table model,
- historical backfill semantics,
- indexing strategy for confirmed-only retrieval (`(active, claim_confirmation_state, project_id)` / embedding lane).
