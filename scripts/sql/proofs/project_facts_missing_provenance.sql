-- Finds project_facts rows with inconsistent provenance pointers.
-- Run: scripts/query.sh --file scripts/sql/proofs/project_facts_missing_provenance.sql

with bad as (
  select
    pf.id,
    pf.project_id,
    pf.fact_kind,
    pf.as_of_at,
    pf.observed_at,
    pf.interaction_id,
    pf.evidence_event_id,
    pf.source_span_id,
    pf.source_char_start,
    pf.source_char_end
  from public.project_facts pf
  where
    -- Char offsets must be all-or-nothing
    (pf.source_char_start is null) <> (pf.source_char_end is null)
    -- If char offsets exist, we expect a span pointer too
    or (pf.source_char_start is not null and pf.source_span_id is null)
)
select *
from bad
order by observed_at desc
limit 200;

