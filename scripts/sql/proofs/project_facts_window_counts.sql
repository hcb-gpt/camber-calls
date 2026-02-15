-- Template: counts of AS_OF facts within a default 90d window ending at t_call.
-- Edit the interaction_id literal, then run:
--   scripts/query.sh --file scripts/sql/proofs/project_facts_window_counts.sql

with params as (
  select
    'cll_REPLACE_ME'::text as interaction_id,
    interval '90 days' as lookback
),
t_call as (
  select
    i.interaction_id,
    i.event_at_utc as t_call_utc,
    (i.event_at_utc - p.lookback) as window_start_utc
  from public.interactions i
  join params p on p.interaction_id = i.interaction_id
),
facts as (
  select
    pf.*,
    t.t_call_utc,
    t.window_start_utc
  from public.project_facts pf
  join t_call t on t.interaction_id = pf.interaction_id
)
select
  interaction_id,
  count(*) filter (where as_of_at <= t_call_utc and as_of_at >= window_start_utc) as as_of_in_window,
  count(*) filter (where as_of_at <= t_call_utc and as_of_at < window_start_utc) as as_of_before_window,
  count(*) filter (where as_of_at > t_call_utc) as post_hoc
from facts
group by interaction_id
order by interaction_id;

