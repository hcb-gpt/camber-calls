-- Pilot seed: project_facts (v0) with strict provenance via evidence_events (source_type='manual').
--
-- IMPORTANT
-- - This file MUTATES DATA. Do NOT run via `scripts/query.sh`.
-- - Run via psql (or equivalent) with appropriate credentials.
-- - This script ends with ROLLBACK by default. To apply, change to COMMIT intentionally.
--
-- Goal
-- - Seed a tiny set of high-signal, attribution-relevant facts for 1 project to validate:
--   - inserts succeed
--   - provenance pointers are present (evidence_event_id)
--   - AS_OF vs KNOWN_AS_OF semantics can be tested in GT without “now leakage”
--
-- After running (even in ROLLBACK), you can use:
-- - `scripts/sql/proofs/project_facts_missing_provenance.sql`
-- - `scripts/sql/proofs/project_facts_window_counts.sql`
-- - `scripts/sql/proofs/project_facts_now_leakage_template.sql`
-- - `scripts/sql/proofs/project_facts_seed_counts_by_kind.sql`
--
-- -----------------------------------------------------------------------------
-- EDIT ME (required)
-- -----------------------------------------------------------------------------
-- Replace:
-- - project_id: target project UUID
-- - as_of_at: effective time (e.g. plan issue date in UTC)
--
-- You can add/remove facts in the `seed_facts` CTE.
-- Keep `fact_payload` small + typed.
--
begin;

with params as (
  select
    '00000000-0000-0000-0000-000000000000'::uuid as project_id,
    '2025-09-04T04:00:00Z'::timestamptz as as_of_at,
    now()::timestamptz as observed_at,
    ('manual_seed:project_facts_v0:' || encode(gen_random_bytes(8), 'hex'))::text as source_id
),
manual_evidence as (
  insert into public.evidence_events (
    source_type,
    source_id,
    transcript_variant,
    occurred_at_utc,
    metadata
  )
  select
    'manual',
    p.source_id,
    null,
    p.as_of_at,
    jsonb_build_object(
      'seed_script', 'scripts/backfills/project_facts_seed_pilot_v0.sql',
      'seed_kind', 'project_facts_seed_pilot_v0',
      'notes', 'Pilot seed for world model validation (facts only; no pipeline integration).'
    )
  from params p
  returning evidence_event_id
),
seed_facts as (
  -- Keep these as “rare / disambiguating” anchors so retrieval has signal without prompt hacks.
  -- Fact taxonomy is intentionally loose in v0: fact_kind + jsonb payload.
  select
    'scope.feature'::text as fact_kind,
    jsonb_build_object(
      'feature', 'site.alias.primary',
      'value', 'Enterprise',
      'tags', jsonb_build_array('PLANS_GT', 'ALIAS'),
      'confidence', 0.90
    ) as fact_payload
  union all select
    'scope.feature',
    jsonb_build_object('feature','space.scullery.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.98)
  union all select
    'scope.feature',
    jsonb_build_object('feature','envelope.window.material','value','steel','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90)
  union all select
    'scope.feature',
    jsonb_build_object('feature','feature.motorized_screens','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.95)
)
insert into public.project_facts (
  project_id,
  as_of_at,
  observed_at,
  fact_kind,
  fact_payload,
  evidence_event_id
)
select
  p.project_id,
  p.as_of_at,
  p.observed_at,
  sf.fact_kind,
  sf.fact_payload,
  me.evidence_event_id
from params p
cross join manual_evidence me
join seed_facts sf on true;

-- Default: do not apply.
rollback;

