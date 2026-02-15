# Project facts (time-synced world model) v0

This adds a minimal `project_facts` table and a helper function `project_facts_as_of(project_id, as_of_at)` for time-synced retrieval.

## Apply / verify

- Migration: `supabase/migrations/20260215254000_create_project_facts_table.sql`
- Verify (read-only):
  - `scripts/query.sh --file scripts/proofs/project_facts_schema_check_v0.sql`

## Example: store + retrieve “scullery” fact (Woodbery)

Project id reference (current DB): `7db5e186-7dda-4c2c-b85e-7235b67e06d8` (Woodbery Residence)

Insert example (manual; run with `psql`, not `scripts/query.sh`):

```sql
insert into public.project_facts (
  project_id,
  fact_key,
  fact_value,
  as_of_at,
  source_kind,
  source_quote,
  confidence
) values (
  '7db5e186-7dda-4c2c-b85e-7235b67e06d8',
  'feature.scullery',
  jsonb_build_object('value', true),
  '2026-02-14T16:39:19Z',
  'manual',
  'scullery (example fact)',
  1.0
);
```

Retrieve as-of:

```sql
select *
from public.project_facts_as_of(
  '7db5e186-7dda-4c2c-b85e-7235b67e06d8',
  '2026-02-14T23:59:59Z'
)
where fact_key = 'feature.scullery';
```

