-- spotcheck_queue.sql
--
-- Purpose:
--   Fast, repeatable "what does the pipeline think?" spotcheck for one call.
--
-- Usage:
--   psql "$DATABASE_URL" -v interaction_id='cll_...' -f scripts/spotcheck_queue.sql
--
-- Notes:
-- - journal_claims uses `call_id` (text) = interactions.interaction_id (NOT interactions.id).
-- - review_queue uses `interaction_id` (text) and/or `span_id` (uuid).

\set ON_ERROR_STOP on

\echo '=== SPOTCHECK QUEUE (scoreboard) ==='

with
params as (select :'interaction_id'::text as interaction_id),

spans_all as (
  select
    s.id as span_id,
    s.segment_generation as generation,
    s.span_index,
    s.char_start,
    s.char_end
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),

max_gen as (select coalesce(max(generation), 0) as gen_max from spans_all),

spans as (
  select *
  from spans_all
  where generation = (select gen_max from max_gen)
),

latest_attr as (
  select distinct on (sa.span_id)
    sa.span_id,
    sa.decision,
    sa.needs_review,
    sa.confidence,
    sa.project_id,
    sa.applied_project_id,
    sa.attribution_source,
    sa.model_id,
    sa.prompt_version,
    sa.attributed_at
  from public.span_attributions sa
  join spans s on s.span_id = sa.span_id
  order by sa.span_id, sa.attributed_at desc
),

rq as (
  select
    rq.id,
    rq.span_id,
    rq.status,
    rq.reason_codes,
    rq.module,
    rq.created_at,
    rq.resolved_at,
    rq.resolution_action,
    cs.interaction_id as span_interaction_id,
    cs.is_superseded
  from public.review_queue rq
  join params p on p.interaction_id = rq.interaction_id
  left join public.conversation_spans cs on cs.id = rq.span_id
),

rq_latest as (
  select
    rq.id,
    rq.span_id,
    rq.status,
    rq.reason_codes,
    rq.module,
    rq.created_at,
    rq.resolved_at,
    rq.resolution_action
  from rq
  join spans s on s.span_id = rq.span_id
),

needs_review_spans as (
  select
    s.span_id
  from spans s
  join latest_attr a on a.span_id = s.span_id
  where a.decision = 'review' or a.needs_review = true
),

review_gaps as (
  select n.span_id
  from needs_review_spans n
  left join rq_latest rq on rq.span_id = n.span_id
  where rq.id is null
),

latest_spans_missing_attr as (
  select s.span_id
  from spans s
  left join latest_attr a on a.span_id = s.span_id
  where a.span_id is null
),

pending_on_superseded as (
  select rq.id
  from rq
  where rq.status = 'pending'
    and rq.span_id is not null
    and (
      rq.span_interaction_id is null
      or rq.span_interaction_id <> (select interaction_id from params)
      or rq.is_superseded = true
    )
),

pending_null_span as (
  select rq.id
  from rq
  where rq.status = 'pending'
    and rq.span_id is null
)

select
  p.interaction_id,
  (select gen_max from max_gen) as latest_generation,
  (select count(*) from spans)::int as spans_latest_gen,
  (select count(*) from latest_attr)::int as latest_attr_rows,
  (select count(*) from rq_latest)::int as review_queue_rows_for_latest_gen,
  (select count(*) from review_gaps)::int as review_gaps,
  (select count(*) from latest_spans_missing_attr)::int as latest_active_spans_missing_attr,
  (select count(*) from pending_on_superseded)::int as pending_on_superseded,
  (select count(*) from pending_null_span)::int as pending_null_span,
  (select count(*) from public.journal_claims jc join params p2 on p2.interaction_id = jc.call_id where jc.active = true)::int as active_journal_claims,
  case
    when (select count(*) from spans) = 0 then 'FAIL_NO_ACTIVE_SPANS'
    when (select count(*) from latest_spans_missing_attr) > 0 then 'FAIL_UNCOVERED_LATEST_SPANS'
    when (select count(*) from pending_on_superseded) > 0 then 'FAIL_PENDING_SUPERSEDED'
    when (select count(*) from pending_null_span) > 0 then 'FAIL_PENDING_NULL_SPAN'
    when (select count(*) from review_gaps) = 0 then 'PASS'
    else 'FAIL_REVIEW_GAP'
  end as verdict
from params p;

\echo ''
\echo '=== SPOTCHECK QUEUE (spans + coverage) ==='

with
params as (select :'interaction_id'::text as interaction_id),

spans_all as (
  select
    s.id as span_id,
    s.segment_generation as generation,
    s.span_index,
    s.char_start,
    s.char_end
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),

max_gen as (select coalesce(max(generation), 0) as gen_max from spans_all),

spans as (
  select *
  from spans_all
  where generation = (select gen_max from max_gen)
),

latest_attr as (
  select distinct on (sa.span_id)
    sa.span_id,
    sa.decision,
    sa.needs_review,
    sa.confidence,
    coalesce(sa.applied_project_id, sa.project_id) as effective_project_id,
    sa.attribution_source,
    sa.model_id,
    sa.prompt_version,
    sa.attributed_at
  from public.span_attributions sa
  join spans s on s.span_id = sa.span_id
  order by sa.span_id, sa.attributed_at desc
),

rq as (
  select
    rq.span_id,
    rq.status,
    rq.module,
    rq.reason_codes
  from public.review_queue rq
  join spans s on s.span_id = rq.span_id
)

select
  s.span_index,
  s.span_id,
  s.char_start,
  s.char_end,
  case when a.span_id is not null then true else false end as has_attr,
  case when r.span_id is not null then true else false end as has_review_queue,
  a.decision,
  a.needs_review,
  a.confidence,
  a.effective_project_id,
  a.attribution_source,
  a.model_id,
  a.prompt_version,
  r.status as review_status,
  r.module as review_module,
  r.reason_codes as review_reason_codes,
  case
    when a.span_id is null and r.span_id is null then 'UNCOVERED'
    when a.span_id is not null and r.span_id is not null then 'DOUBLE_COVERED'
    when (a.decision = 'review' or a.needs_review = true) and r.span_id is null then 'REVIEW_GAP'
    else 'OK'
  end as coverage_class
from spans s
left join latest_attr a on a.span_id = s.span_id
left join rq r on r.span_id = s.span_id
order by s.span_index asc;

\echo ''
\echo '=== SPOTCHECK QUEUE (journal_claims summary, active) ==='

with
params as (select :'interaction_id'::text as interaction_id)
select
  jc.id,
  jc.claim_id,
  jc.claim_type,
  left(jc.claim_text, 140) as claim_text_excerpt,
  jc.claim_project_id,
  jc.claim_project_confidence,
  jc.attribution_confidence,
  jc.epistemic_status,
  jc.warrant_level,
  jc.pointer_type,
  jc.speaker_label,
  jc.source_span_id
from public.journal_claims jc
join params p on p.interaction_id = jc.call_id
where jc.active = true
order by jc.claim_project_confidence desc nulls last, jc.attribution_confidence desc nulls last
limit 200;
