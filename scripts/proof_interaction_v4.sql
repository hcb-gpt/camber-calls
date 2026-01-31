-- proof_interaction_v4_single_span_warning.sql
-- Purpose: proof SQL v4 (warn-only single-span sanity signal).
-- Adds WARN line when transcript_chars > 2000 AND spans_total == 1.
-- WARNING DOES NOT CHANGE verdict; merges must not be blocked by this signal.
--
-- Usage:
--   psql "$DATABASE_URL" -v interaction_id='cll_...' -f scripts/proof_interaction_v4.sql
--
-- Definitions:
-- - Active spans: conversation_spans.is_superseded=false
-- - Latest active generation: max(segment_generation) among active spans
-- - spans_total: count(active spans in latest generation)
-- - transcript_chars: max(char_end) among active spans in latest generation (approx total transcript length)
-- - Needs review: (decision='review' OR needs_review=true)
-- - Review gap: needs-review spans with NO review_queue row
-- - Receipt quality checks: unchanged from v3 (fail-closed) — see receipt_fail_* CTEs.

\echo '=== SCOREBOARD (single row) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans_all as (
  select
    s.id as span_id,
    s.interaction_id,
    s.segment_generation as generation,
    s.span_index,
    s.char_start,
    s.char_end
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),

max_gen as (
  select coalesce(max(generation), 0) as gen_max
  from active_spans_all
),

active_spans as (
  select *
  from active_spans_all
  where generation = (select gen_max from max_gen)
),

spans_total as (
  select count(*)::int as spans_total from active_spans
),

transcript_chars as (
  select coalesce(max(char_end), 0)::int as transcript_chars
  from active_spans
),

attrs as (
  select
    sa.*,
    -- evidence_receipt discovery (jsonb or column)
    coalesce(
      jsonb_path_query_first(to_jsonb(sa), '$.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.raw_response.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.router_raw.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.ai_router_response.evidence_receipt')
    ) as evidence_receipt_j,
    -- missing_evidence discovery (jsonb or column)
    coalesce(
      jsonb_path_query_first(to_jsonb(sa), '$.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.raw_response.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.router_raw.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.ai_router_response.missing_evidence')
    ) as missing_evidence_j
  from public.span_attributions sa
),

active_attrs as (
  select
    a.span_id,
    a.project_id,
    a.decision,
    a.needs_review,
    a.confidence,
    a.evidence_receipt_j,
    a.missing_evidence_j
  from attrs a
  join active_spans s on s.span_id = a.span_id
),

review_items as (
  select count(*)::int as review_items
  from public.review_queue rq
  join active_spans s on s.span_id = rq.span_id
),

needs_review_spans as (
  select distinct a.span_id
  from active_attrs a
  where a.decision = 'review' or a.needs_review = true
),

review_gaps as (
  select n.span_id
  from needs_review_spans n
  left join public.review_queue rq on rq.span_id = n.span_id
  where rq.id is null
),

receipt_fail_assign as (
  select a.span_id,
         case
           when a.evidence_receipt_j is null then 'ASSIGN_MISSING_EVIDENCE_RECEIPT'
           when coalesce(jsonb_array_length(a.evidence_receipt_j->'primary_evidence'), 0) < 1 then 'ASSIGN_MISSING_PRIMARY_EVIDENCE'
           when nullif(trim(coalesce(a.evidence_receipt_j->>'safety_rationale','')), '') is null then 'ASSIGN_MISSING_SAFETY_RATIONALE'
           else null
         end as fail_reason
  from active_attrs a
  where a.decision = 'assign'
),

receipt_fail_review as (
  select a.span_id,
         case
           when a.missing_evidence_j is null then 'REVIEW_MISSING_MISSING_EVIDENCE'
           when jsonb_typeof(a.missing_evidence_j) = 'array' and coalesce(jsonb_array_length(a.missing_evidence_j), 0) < 2 then 'REVIEW_MISSING_EVIDENCE_TOO_SHORT'
           when jsonb_typeof(a.missing_evidence_j) = 'string' and nullif(trim(a.missing_evidence_j #>> '{}'), '') is null then 'REVIEW_MISSING_MISSING_EVIDENCE'
           else null
         end as fail_reason
  from active_attrs a
  where (a.decision in ('review','none') or a.needs_review = true)
),

receipt_fails as (
  select * from receipt_fail_assign where fail_reason is not null
  union all
  select * from receipt_fail_review where fail_reason is not null
),

override_reseeds as (
  select count(*)::int as override_reseeds
  from public.override_log ol
  join params p on p.interaction_id = ol.interaction_id
  where ol.entity_type = 'reseed'
),

warn_single_span as (
  select
    case
      when (select transcript_chars from transcript_chars) > 2000
       and (select spans_total from spans_total) = 1
      then true else false end as warn_single_span,
    case
      when (select transcript_chars from transcript_chars) > 2000
       and (select spans_total from spans_total) = 1
      then 'WARNING_SINGLE_SPAN_SANITY: transcript_chars>2000 AND spans_total==1 (warn-only; investigate de-chunking)'
      else null end as warn_text
)

select
  p.interaction_id,
  (select gen_max from max_gen) as gen_max,
  (select spans_total from spans_total) as spans_total,
  (select transcript_chars from transcript_chars) as transcript_chars,
  (select count(*) from active_attrs)::int as attributions_count,
  (select review_items from review_items) as review_queue_count,
  (select count(*) from review_gaps)::int as gap_count,
  (select count(*) from receipt_fails)::int as receipt_fail_total,
  (select override_reseeds from override_reseeds) as override_reseeds,
  (select warn_single_span from warn_single_span) as warn_single_span,
  case
    when (select count(*) from active_spans) = 0 then 'FAIL_NO_ACTIVE_SPANS'
    when (select count(*) from review_gaps) > 0 then 'FAIL_REVIEW_GAP'
    when (select count(*) from receipt_fails) > 0 then 'FAIL_RECEIPT_QUALITY'
    else 'PASS'
  end as verdict
from params p;

\echo ''
\echo '=== WARNING LINE (warn-only; should not fail merges) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans_all as (
  select
    s.segment_generation as generation,
    s.is_superseded,
    s.char_end
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),
max_gen as (
  select coalesce(max(generation), 0) as gen_max
  from active_spans_all
),
active_latest as (
  select * from active_spans_all where generation = (select gen_max from max_gen)
),
spans_total as (select count(*)::int as spans_total from active_latest),
transcript_chars as (select coalesce(max(char_end),0)::int as transcript_chars from active_latest)
select
  case
    when (select transcript_chars from transcript_chars) > 2000
     and (select spans_total from spans_total) = 1
    then 'WARNING_SINGLE_SPAN_SANITY: transcript_chars>2000 AND spans_total==1 (warn-only)'
    else 'OK_NO_SINGLE_SPAN_WARNING'
  end as warning;

\echo ''
\echo '=== GAP DETECTOR ROWS (must be empty on PASS) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans_all as (
  select
    s.id as span_id,
    s.segment_generation as generation
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),
max_gen as (
  select coalesce(max(generation), 0) as gen_max
  from active_spans_all
),
active_spans as (
  select * from active_spans_all where generation = (select gen_max from max_gen)
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

\echo ''
\echo '=== RECEIPT QUALITY FAIL ROWS (must be empty on PASS) ==='

with
params as (select :'interaction_id'::text as interaction_id),

active_spans_all as (
  select
    s.id as span_id,
    s.segment_generation as generation
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
  where s.is_superseded = false
),
max_gen as (
  select coalesce(max(generation), 0) as gen_max
  from active_spans_all
),
active_spans as (
  select * from active_spans_all where generation = (select gen_max from max_gen)
),

attrs as (
  select
    sa.*,
    coalesce(
      jsonb_path_query_first(to_jsonb(sa), '$.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.raw_response.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.router_raw.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.ai_router_response.evidence_receipt')
    ) as evidence_receipt_j,
    coalesce(
      jsonb_path_query_first(to_jsonb(sa), '$.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.raw_response.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.router_raw.missing_evidence'),
      jsonb_path_query_first(to_jsonb(sa), '$.ai_router_response.missing_evidence')
    ) as missing_evidence_j
  from public.span_attributions sa
),

active_attrs as (
  select
    a.span_id,
    a.project_id,
    a.decision,
    a.needs_review,
    a.confidence,
    a.evidence_receipt_j,
    a.missing_evidence_j
  from attrs a
  join active_spans s on s.span_id = a.span_id
),

fails as (
  select
    a.span_id,
    a.project_id,
    a.decision,
    a.needs_review,
    a.confidence,
    case
      when a.decision = 'assign' and a.evidence_receipt_j is null then 'ASSIGN_MISSING_EVIDENCE_RECEIPT'
      when a.decision = 'assign' and coalesce(jsonb_array_length(a.evidence_receipt_j->'primary_evidence'), 0) < 1 then 'ASSIGN_MISSING_PRIMARY_EVIDENCE'
      when a.decision = 'assign' and nullif(trim(coalesce(a.evidence_receipt_j->>'safety_rationale','')), '') is null then 'ASSIGN_MISSING_SAFETY_RATIONALE'
      when (a.decision in ('review','none') or a.needs_review = true) and a.missing_evidence_j is null then 'REVIEW_MISSING_MISSING_EVIDENCE'
      when (a.decision in ('review','none') or a.needs_review = true) and jsonb_typeof(a.missing_evidence_j)='array' and coalesce(jsonb_array_length(a.missing_evidence_j),0) < 2 then 'REVIEW_MISSING_EVIDENCE_TOO_SHORT'
      when (a.decision in ('review','none') or a.needs_review = true) and jsonb_typeof(a.missing_evidence_j)='string' and nullif(trim(a.missing_evidence_j #>> '{}'), '') is null then 'REVIEW_MISSING_MISSING_EVIDENCE'
      else null
    end as fail_reason
  from active_attrs a
)

select
  span_id,
  project_id,
  decision,
  needs_review,
  confidence,
  fail_reason
from fails
where fail_reason is not null
order by confidence desc nulls last
limit 50;
