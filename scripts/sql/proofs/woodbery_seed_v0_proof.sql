-- Proof: Woodbery world-model seed v0 inserted facts + provenance sanity checks.
-- Run (read-only): scripts/query.sh --file scripts/sql/proofs/woodbery_seed_v0_proof.sql

with params as (
  select
    '7db5e186-7dda-4c2c-b85e-7235b67e06d8'::uuid as project_id,
    'scripts/backfills/woodbery_seed_v0.sql'::text as seed_script
),
facts as (
  select
    pf.*,
    ee.source_type,
    ee.metadata
  from public.project_facts pf
  left join public.evidence_events ee on ee.evidence_event_id = pf.evidence_event_id
  join params p on p.project_id = pf.project_id
)
select
  count(*)::int as fact_count,
  count(*) filter (where evidence_event_id is not null)::int as with_evidence_event_id,
  count(*) filter (where source_type = 'manual')::int as manual_source_count,
  count(*) filter (where (metadata->>'seed_script') = (select seed_script from params))::int as seed_script_match_count,
  min(as_of_at) as min_as_of_at,
  max(as_of_at) as max_as_of_at,
  min(observed_at) as min_observed_at,
  max(observed_at) as max_observed_at
from facts;

-- Breakdown by fact_kind
select
  fact_kind,
  count(*)::int as fact_count
from public.project_facts
where project_id = '7db5e186-7dda-4c2c-b85e-7235b67e06d8'
group by fact_kind
order by fact_count desc, fact_kind asc;

