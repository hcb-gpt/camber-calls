-- Proof: counts of recently observed project_facts by fact_kind (seed sanity check).
-- Run: scripts/query.sh --file scripts/sql/proofs/project_facts_seed_counts_by_kind.sql

with recent as (
  select *
  from public.project_facts
  where observed_at >= (now() - interval '24 hours')
)
select
  fact_kind,
  count(*) as fact_count,
  count(*) filter (where evidence_event_id is not null) as with_evidence_event_id,
  min(observed_at) as min_observed_at,
  max(observed_at) as max_observed_at
from recent
group by fact_kind
order by fact_count desc, fact_kind asc;

