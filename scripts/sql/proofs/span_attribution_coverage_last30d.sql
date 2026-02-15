-- Coverage snapshot for active spans over last 30 days.
-- "Covered" = has any span_attributions row OR has a pending/open review_queue row.
-- Run: scripts/query.sh --file scripts/sql/proofs/span_attribution_coverage_last30d.sql

with spans as (
  select
    cs.id as span_id,
    cs.interaction_id,
    cs.span_index
  from public.conversation_spans cs
  join public.interactions i on i.interaction_id = cs.interaction_id
  where
    cs.is_superseded = false
    and coalesce(i.event_at_utc, i.ingested_at_utc) >= (now() - interval '30 days')
),
attr as (
  select distinct sa.span_id
  from public.span_attributions sa
),
rq as (
  select distinct rq.span_id
  from public.review_queue rq
  where rq.span_id is not null
    and rq.status in ('pending', 'open')
)
select
  count(*)::bigint as active_spans_last30d,
  count(*) filter (where attr.span_id is not null)::bigint as covered_by_attribution,
  count(*) filter (where attr.span_id is null and rq.span_id is not null)::bigint as covered_by_pending_review,
  count(*) filter (where attr.span_id is null and rq.span_id is null)::bigint as uncovered,
  round(
    100.0 * (count(*) filter (where attr.span_id is not null or rq.span_id is not null))::numeric
      / nullif(count(*)::numeric, 0),
    2
  ) as coverage_pct
from spans s
left join attr on attr.span_id = s.span_id
left join rq on rq.span_id = s.span_id;

