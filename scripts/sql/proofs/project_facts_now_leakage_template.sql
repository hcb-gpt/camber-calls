-- Template: label project_facts as AS_OF vs POST_HOC for a given interaction (t_call = interactions.event_at_utc).
-- Edit the interaction_id literal, then run:
--   scripts/query.sh --file scripts/sql/proofs/project_facts_now_leakage_template.sql

with params as (
  select 'cll_REPLACE_ME'::text as interaction_id
),
t_call as (
  select
    i.interaction_id,
    i.event_at_utc as t_call_utc
  from public.interactions i
  join params p on p.interaction_id = i.interaction_id
),
labeled as (
  select
    pf.id,
    pf.project_id,
    pf.fact_kind,
    pf.as_of_at,
    pf.observed_at,
    t.t_call_utc,
    case when pf.as_of_at <= t.t_call_utc then 'AS_OF' else 'POST_HOC' end as time_relation
  from public.project_facts pf
  join t_call t on t.interaction_id = pf.interaction_id
)
select *
from labeled
order by as_of_at desc
limit 200;

