-- regression_detector_v2.sql
-- Goal: top regressions section for daily digest (last 24h vs baseline).
-- Params: :window_start (timestamptz), :window_end (timestamptz)
-- Baseline: prior 7 days before window_start.

with w as (
  select :window_start::timestamptz as ws, :window_end::timestamptz as we
),
latest_window as (
  select distinct on (interaction_id)
    interaction_id,
    created_at,
    spans_total,
    spans_active,
    review_gap,
    override_reseeds,
    transcript_chars,
    case when coalesce(review_gap,0)=0 and coalesce(spans_active,0) > 0 then 1 else 0 end as is_pass
  from pipeline_scoreboard_snapshots, w
  where created_at >= w.ws and created_at < w.we
  order by interaction_id, created_at desc
),
latest_baseline as (
  select distinct on (interaction_id)
    interaction_id,
    created_at,
    spans_total,
    spans_active,
    review_gap,
    override_reseeds,
    transcript_chars,
    case when coalesce(review_gap,0)=0 and coalesce(spans_active,0) > 0 then 1 else 0 end as is_pass
  from pipeline_scoreboard_snapshots, w
  where created_at >= (w.ws - interval '7 days') and created_at < w.ws
  order by interaction_id, created_at desc
),
agg_window as (
  select
    count(*) as calls_total,
    sum(case when is_pass=0 then 1 else 0 end) as fail_calls,
    sum(case when coalesce(review_gap,0) > 0 then 1 else 0 end) as gap_calls,
    sum(case when coalesce(transcript_chars,0) > 2000 and coalesce(spans_total,0)=1 then 1 else 0 end) as single_span_calls,
    avg(coalesce(override_reseeds,0))::numeric as avg_reseed_churn
  from latest_window
),
agg_base as (
  select
    count(*) as calls_total,
    sum(case when is_pass=0 then 1 else 0 end) as fail_calls,
    sum(case when coalesce(review_gap,0) > 0 then 1 else 0 end) as gap_calls,
    sum(case when coalesce(transcript_chars,0) > 2000 and coalesce(spans_total,0)=1 then 1 else 0 end) as single_span_calls,
    avg(coalesce(override_reseeds,0))::numeric as avg_reseed_churn
  from latest_baseline
),
summary as (
  select
    aw.calls_total as window_calls,
    ab.calls_total as base_calls,
    aw.fail_calls as window_fail_calls,
    ab.fail_calls as base_fail_calls,
    aw.gap_calls as window_gap_calls,
    ab.gap_calls as base_gap_calls,
    aw.single_span_calls as window_single_span_calls,
    ab.single_span_calls as base_single_span_calls,
    round(aw.avg_reseed_churn, 4) as window_avg_reseed_churn,
    round(ab.avg_reseed_churn, 4) as base_avg_reseed_churn,
    case when ab.avg_reseed_churn is null or ab.avg_reseed_churn = 0 then null
         else round((aw.avg_reseed_churn / ab.avg_reseed_churn)::numeric, 2)
    end as reseed_churn_ratio
  from agg_window aw cross join agg_base ab
)
select
  'summary' as section,
  to_jsonb(summary.*) as data
from summary

union all

select
  'top_gap_calls' as section,
  jsonb_agg(to_jsonb(t.*) order by t.review_gap desc, t.created_at desc) as data
from (
  select interaction_id, created_at, review_gap, spans_total, transcript_chars
  from latest_window
  where coalesce(review_gap,0) > 0
  order by review_gap desc, created_at desc
  limit 10
) t

union all

select
  'top_fail_calls' as section,
  jsonb_agg(to_jsonb(t.*) order by t.created_at desc) as data
from (
  select interaction_id, created_at, spans_total, spans_active, transcript_chars
  from latest_window
  where is_pass = 0
  order by created_at desc
  limit 10
) t

union all

select
  'top_single_span_warnings' as section,
  jsonb_agg(to_jsonb(t.*) order by t.transcript_chars desc, t.created_at desc) as data
from (
  select interaction_id, created_at, spans_total, transcript_chars
  from latest_window
  where coalesce(transcript_chars,0) > 2000 and coalesce(spans_total,0) = 1
  order by transcript_chars desc, created_at desc
  limit 10
) t;
