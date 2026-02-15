-- Template: coverage summary for a single interaction_id.
-- Edit the interaction_id literal, then run:
--   scripts/query.sh --file scripts/sql/proofs/span_attribution_coverage_for_interaction_template.sql

with params as (
  select 'cll_REPLACE_ME'::text as interaction_id
),
spans as (
  select
    cs.id as span_id,
    cs.interaction_id,
    cs.span_index
  from public.conversation_spans cs
  join params p on p.interaction_id = cs.interaction_id
  where cs.is_superseded = false
),
attr as (
  select distinct sa.span_id
  from public.span_attributions sa
  join spans s on s.span_id = sa.span_id
),
rq as (
  select distinct rq.span_id
  from public.review_queue rq
  join spans s on s.span_id = rq.span_id
  where rq.status in ('pending', 'open')
)
select
  (select interaction_id from params) as interaction_id,
  count(*)::bigint as active_spans,
  count(*) filter (where attr.span_id is not null)::bigint as covered_by_attribution,
  count(*) filter (where attr.span_id is null and rq.span_id is not null)::bigint as covered_by_pending_review,
  count(*) filter (where attr.span_id is null and rq.span_id is null)::bigint as uncovered
from spans s
left join attr on attr.span_id = s.span_id
left join rq on rq.span_id = s.span_id;

