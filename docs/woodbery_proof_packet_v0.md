# Woodbery World Model Proof Packet v0

**Goal:** demonstrate that Woodbery plan-derived disambiguators are present in `project_facts` with strict provenance,
and become available to `context-assembly` / `ai-router` when `WORLD_MODEL_FACTS_ENABLED=true`.

## Artifacts

| Artifact         | Path                                                                                              | Notes                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Seed SQL         | `scripts/backfills/woodbery_seed_v0.sql`                                                          | Seeds 30+ PLANS_GT facts with manual evidence provenance (ROLLBACK by default) |
| Proof SQL        | `scripts/sql/proofs/woodbery_seed_v0_proof.sql`                                                   | Verifies counts + provenance + time fields                                     |
| Source fact pack | `orbit/orbit/docs/camber/world_model/inputs/2026-02-16/woodbery/woodbery_plans_fact_pack_v0.json` | Human-curated disambiguator set                                                |

## Preconditions (prod)

- `public.project_facts` exists (migration applied)
- `WORLD_MODEL_FACTS_ENABLED=true` and `WORLD_MODEL_FACTS_MAX_PER_PROJECT` set (Supabase secrets)

## How to Run (prod)

1. Apply seed (intentional write):

```bash
psql "$DATABASE_URL" -f scripts/backfills/woodbery_seed_v0.sql
```

2. Validate (read-only):

```bash
scripts/query.sh --file scripts/sql/proofs/woodbery_seed_v0_proof.sql
```

## Expected Results

1. Facts exist for Woodbery `project_id=7db5e186-7dda-4c2c-b85e-7235b67e06d8`.
2. All facts have `evidence_event_id` pointing to a `manual` `evidence_events` row with:
   - `metadata.seed_script = scripts/backfills/woodbery_seed_v0.sql`
3. `as_of_at` and `observed_at` align to the plan issue date so KNOWN_AS_OF retrieval can surface them for calls after
   that date.
