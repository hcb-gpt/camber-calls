-- proof_interaction.sql (v2)
-- STRAT TURN 72: Consolidated proof SQL with 3-part output
--
-- Purpose: one-shot proof SQL for one interaction_id:
--   1) SCOREBOARD row (+ PASS/FAIL)
--   2) Top 10 spans with status (active/superseded)
--   3) Gap detector rows (must be empty on PASS)
--
-- Usage:
--   psql "$DATABASE_URL" -v interaction_id='cll_...' -f scripts/proof_interaction.sql
--
-- Notes:
-- - Treats active spans as is_superseded=false.
-- - Treats "needs review" as (decision='review' OR needs_review=true).
-- - "review_gap" counts spans needing review with NO review_queue row.

\echo '=== SCOREBOARD (single row) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans as (
  select
    s.id as span_id,
    s.interaction_id,
    s.segment_generation as generation,
    s.span_index,
    s.is_superseded
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),

gen_max as (
  select coalesce(max(generation), 0) as gen_max from active_spans
),

attributions as (
  select count(*)::int as attributions
  from public.span_attributions sa
  join active_spans a on a.span_id = sa.span_id
),

review_items as (
  select count(*)::int as review_items
  from public.review_queue rq
  join active_spans a on a.span_id = rq.span_id
),

needs_review_spans as (
  select distinct sa.span_id
  from public.span_attributions sa
  join active_spans a on a.span_id = sa.span_id
  where sa.decision = 'review' or sa.needs_review = true
),

review_gaps as (
  select n.span_id
  from needs_review_spans n
  left join public.review_queue rq on rq.span_id = n.span_id
  where rq.id is null
),

override_reseeds as (
  select count(*)::int as override_reseeds
  from public.override_log ol
  join params p on p.interaction_id = ol.interaction_id
  where ol.entity_type = 'reseed'
)

select
  p.interaction_id,
  (select gen_max from gen_max) as gen_max,
  (select count(*) from active_spans)::int as spans_active,
  (select attributions from attributions) as attributions,
  (select review_items from review_items) as review_items,
  (select count(*) from review_gaps)::int as review_gap,
  (select override_reseeds from override_reseeds) as override_reseeds,
  case
    when (select count(*) from active_spans) = 0 then 'FAIL_NO_ACTIVE_SPANS'
    when (select count(*) from review_gaps) = 0 then 'PASS'
    else 'FAIL_REVIEW_GAP'
  end as verdict
from params p;

\echo ''
\echo '=== TOP 10 SPANS (active + most recent generation) ==='

with
params as (select :'interaction_id'::text as interaction_id),

spans as (
  select
    s.id as span_id,
    s.segment_generation as generation,
    s.span_index,
    s.is_superseded,
    s.char_start,
    s.char_end
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
),

max_gen as (
  select coalesce(max(generation), 0) as gen_max
  from spans
  where is_superseded = false
),

active_latest as (
  select *
  from spans
  where is_superseded = false
    and generation = (select gen_max from max_gen)
),

attr as (
  select
    sa.span_id,
    sa.project_id,
    sa.decision,
    sa.needs_review,
    sa.confidence
  from public.span_attributions sa
),

rq as (
  select
    rq.span_id,
    rq.status as review_status
  from public.review_queue rq
)

select
  s.span_id,
  s.generation,
  s.span_index,
  case when s.is_superseded then 'superseded' else 'active' end as span_status,
  s.char_start,
  s.char_end,
  a.project_id,
  a.decision,
  a.needs_review,
  a.confidence,
  r.review_status
from active_latest s
left join attr a on a.span_id = s.span_id
left join rq r on r.span_id = s.span_id
order by s.span_index asc
limit 10;

\echo ''
\echo '=== GAP DETECTOR ROWS (must be empty on PASS) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans as (
  select s.id as span_id
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),

needs_review_spans as (
  select distinct sa.span_id
  from public.span_attributions sa
  join active_spans a on a.span_id = sa.span_id
  where sa.decision = 'review' or sa.needs_review = true
)

select
  n.span_id,
  sa.decision,
  sa.needs_review,
  sa.confidence
from needs_review_spans n
join public.span_attributions sa on sa.span_id = n.span_id
left join public.review_queue rq on rq.span_id = n.span_id
where rq.id is null
order by sa.confidence desc nulls last
limit 50;
