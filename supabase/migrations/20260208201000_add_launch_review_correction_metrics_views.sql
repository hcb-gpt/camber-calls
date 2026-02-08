-- Stage A launch metrics: correction-rate telemetry views
-- Source: DATA receipt data2_stageA_sql_draft_correction_metrics_v1
-- Scope: analytics-only (no behavioral changes)

begin;

-- Daily correction telemetry: resolved review_queue items vs correction audit rows.
create or replace view public.v_launch_review_correction_daily as
with resolved as (
  select
    date_trunc('day', coalesce(rq.resolved_at, rq.updated_at, rq.created_at))::date as day_utc,
    rq.id as review_queue_id,
    rq.span_id,
    rq.interaction_id,
    coalesce(rq.resolution_action, 'unknown') as resolution_action,
    rq.resolved_by
  from public.review_queue rq
  where rq.status = 'resolved'
),
corrections as (
  select distinct
    ol.review_queue_id
  from public.override_log ol
  where ol.entity_type = 'span_attribution'
    and ol.field_name = 'applied_project_id'
    and ol.review_queue_id is not null
    and (ol.from_value is distinct from ol.to_value)
)
select
  r.day_utc,
  count(*)::bigint as resolved_total,
  count(*) filter (where r.resolution_action = 'confirmed')::bigint as confirmed_total,
  count(*) filter (where r.resolution_action in ('rejected', 'reassigned', 'edited'))::bigint as explicit_change_actions,
  count(c.review_queue_id)::bigint as corrected_total,
  round(100.0 * count(c.review_queue_id)::numeric / nullif(count(*), 0), 2) as correction_rate_pct
from resolved r
left join corrections c
  on c.review_queue_id = r.review_queue_id
group by r.day_utc
order by r.day_utc desc;

comment on view public.v_launch_review_correction_daily is
  'Daily correction telemetry: resolved review_queue items vs rows with span_attribution applied_project_id overrides.';

-- Daily correction telemetry by model/prompt using latest attribution per span.
create or replace view public.v_launch_review_correction_by_model_daily as
with resolved as (
  select
    date_trunc('day', coalesce(rq.resolved_at, rq.updated_at, rq.created_at))::date as day_utc,
    rq.id as review_queue_id,
    rq.span_id,
    rq.interaction_id,
    coalesce(rq.resolution_action, 'unknown') as resolution_action
  from public.review_queue rq
  where rq.status = 'resolved'
),
latest_attr as (
  select distinct on (sa.span_id)
    sa.span_id,
    coalesce(sa.model_id, 'unknown') as model_id,
    coalesce(sa.prompt_version, 'unknown') as prompt_version,
    sa.attributed_at
  from public.span_attributions sa
  order by sa.span_id, sa.attributed_at desc nulls last
),
corrections as (
  select distinct
    ol.review_queue_id
  from public.override_log ol
  where ol.entity_type = 'span_attribution'
    and ol.field_name = 'applied_project_id'
    and ol.review_queue_id is not null
    and (ol.from_value is distinct from ol.to_value)
)
select
  r.day_utc,
  coalesce(la.model_id, 'unknown') as model_id,
  coalesce(la.prompt_version, 'unknown') as prompt_version,
  count(*)::bigint as resolved_total,
  count(c.review_queue_id)::bigint as corrected_total,
  round(100.0 * count(c.review_queue_id)::numeric / nullif(count(*), 0), 2) as correction_rate_pct
from resolved r
left join latest_attr la
  on la.span_id = r.span_id
left join corrections c
  on c.review_queue_id = r.review_queue_id
group by r.day_utc, coalesce(la.model_id, 'unknown'), coalesce(la.prompt_version, 'unknown')
order by r.day_utc desc, model_id, prompt_version;

comment on view public.v_launch_review_correction_by_model_daily is
  'Daily correction telemetry by model_id/prompt_version using latest span attribution for per-day breakdown.';

commit;
