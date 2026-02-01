-- proof_pack.sql
-- One-shot proof pack SQL for a single interaction_id, designed for both local + CI usage.
-- Source: GPT-DEV-2 (STRAT_GPT-DEV-2_20260131T2355Z)
--
-- Requires psql vars:
--   :interaction_id (text)
--   :strict_chunking (int; 1 or 0)
--
-- Output sections:
--   0) STRICT ONE-LINER (grep-friendly): PROOF_PACK_RESULT=PASS|FAIL_...
--   1) SCOREBOARD (single row)
--   2) SPANS BY GENERATION SUMMARY
--   3) COVERAGE OFFENDERS (first 25 uncovered / double-covered)
--
-- Definitions:
-- - Active spans: conversation_spans.is_superseded=false AND generation = max(segment_generation) among active spans
-- - Needs review: (span_attributions.decision='review' OR span_attributions.needs_review=true)
-- - Gap: needs-review spans with NO review_queue row
-- - Uncovered: active span has NO attribution AND NO review_queue row
-- - Double-covered: active span has BOTH attribution AND review_queue row
-- - Strict chunking: FAIL if spans_total < expected_min_spans (deterministic rule) when strict_chunking=1
--
-- expected_min_spans rule (deterministic; no knobs):
--   transcript_chars <= 2000  => 1
--   2001..6000                => 2
--   6001..12000               => 3
--   12001+                    => 4

\if :{?strict_chunking}
\else
\set strict_chunking 1
\endif

with
params as (
  select
    :'interaction_id'::text as interaction_id,
    (:'strict_chunking')::int as strict_chunking
),

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

expected_min_spans as (
  select
    case
      when (select transcript_chars from transcript_chars) <= 2000 then 1
      when (select transcript_chars from transcript_chars) <= 6000 then 2
      when (select transcript_chars from transcript_chars) <= 12000 then 3
      else 4
    end::int as expected_min_spans
),

attrs as (
  select
    sa.*,
    -- evidence_receipt discovery (column or nested jsonb)
    coalesce(
      jsonb_path_query_first(to_jsonb(sa), '$.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.raw_response.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.router_raw.evidence_receipt'),
      jsonb_path_query_first(to_jsonb(sa), '$.ai_router_response.evidence_receipt')
    ) as evidence_receipt_j,
    -- missing_evidence discovery (column or nested jsonb)
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

rq as (
  select rq.span_id, rq.status
  from public.review_queue rq
  join active_spans s on s.span_id = rq.span_id
),

counts as (
  select
    (select count(*) from active_spans)::int as spans_active,
    (select count(*) from active_attrs)::int as attributions_count,
    (select count(*) from rq)::int as review_queue_count
),

uncovered as (
  select s.span_id
  from active_spans s
  left join active_attrs a on a.span_id = s.span_id
  left join rq r on r.span_id = s.span_id
  where a.span_id is null and r.span_id is null
),

double_covered as (
  select s.span_id
  from active_spans s
  join active_attrs a on a.span_id = s.span_id
  join rq r on r.span_id = s.span_id
),

needs_review_spans as (
  select distinct a.span_id
  from active_attrs a
  where a.decision = 'review' or a.needs_review = true
),

review_gaps as (
  select n.span_id
  from needs_review_spans n
  left join rq r on r.span_id = n.span_id
  where r.span_id is null
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

metrics as (
  select
    p.interaction_id,
    (select gen_max from max_gen) as gen_max,
    (select spans_total from spans_total) as spans_total,
    (select transcript_chars from transcript_chars) as transcript_chars,
    (select expected_min_spans from expected_min_spans) as expected_min_spans,
    p.strict_chunking,
    (select spans_active from counts) as spans_active,
    (select attributions_count from counts) as attributions_count,
    (select review_queue_count from counts) as review_queue_count,
    (select count(*) from uncovered)::int as uncovered_count,
    (select count(*) from double_covered)::int as double_covered_count,
    (select count(*) from review_gaps)::int as gap_count,
    (select count(*) from receipt_fails)::int as receipt_fail_total
  from params p
),

collapse_class as (
  select
    case
      when spans_active = 0 then 'NO_ACTIVE_SPANS'
      when strict_chunking = 1 and spans_total < expected_min_spans then 'CHUNK_COLLAPSE_TOO_FEW_SPANS'
      when uncovered_count > 0 then 'UNCOVERED'
      when double_covered_count > 0 then 'DOUBLE_COVERED'
      when gap_count > 0 then 'REVIEW_GAP'
      when receipt_fail_total > 0 then 'RECEIPT_QUALITY'
      else 'NONE'
    end as collapse_class
  from metrics
),

verdict as (
  select
    case
      when spans_active = 0 then 'FAIL_NO_ACTIVE_SPANS'
      when strict_chunking = 1 and spans_total < expected_min_spans then 'FAIL_STRICT_TOO_FEW_SPANS'
      when uncovered_count > 0 then 'FAIL_UNCOVERED'
      when double_covered_count > 0 then 'FAIL_DOUBLE_COVERED'
      when gap_count > 0 then 'FAIL_REVIEW_GAP'
      when receipt_fail_total > 0 then 'FAIL_RECEIPT_QUALITY'
      else 'PASS'
    end as verdict
  from metrics
)

\echo '=== STRICT ONE-LINER (for CI grep) ==='
select
  format(
    'PROOF_PACK_RESULT=%s interaction_id=%s spans_total=%s spans_active=%s transcript_chars=%s expected_min_spans=%s strict_chunking=%s attributions_count=%s review_queue_count=%s uncovered_count=%s double_covered_count=%s gap_count=%s receipt_fail_total=%s collapse_class=%s',
    (select verdict from verdict),
    (select interaction_id from metrics),
    (select spans_total from metrics),
    (select spans_active from metrics),
    (select transcript_chars from metrics),
    (select expected_min_spans from metrics),
    (select strict_chunking from metrics),
    (select attributions_count from metrics),
    (select review_queue_count from metrics),
    (select uncovered_count from metrics),
    (select double_covered_count from metrics),
    (select gap_count from metrics),
    (select receipt_fail_total from metrics),
    (select collapse_class from collapse_class)
  ) as strict_line;

\echo ''
\echo '=== SCOREBOARD (single row) ==='
select
  interaction_id,
  gen_max,
  spans_total,
  spans_active,
  transcript_chars,
  expected_min_spans,
  strict_chunking,
  attributions_count,
  review_queue_count,
  uncovered_count,
  double_covered_count,
  gap_count,
  receipt_fail_total,
  (select collapse_class from collapse_class) as collapse_class,
  (select verdict from verdict) as verdict
from metrics;

\echo ''
\echo '=== SPANS BY GENERATION SUMMARY ==='

with
params as (select :'interaction_id'::text as interaction_id),
spans as (
  select
    s.segment_generation as generation,
    s.id as span_id,
    s.is_superseded
  from public.conversation_spans s
  join params p on p.interaction_id = s.interaction_id
),
active as (select * from spans where is_superseded=false),
gens as (select distinct generation from spans),
counts_by_gen as (
  select
    g.generation,
    coalesce((select count(*) from active a where a.generation=g.generation),0)::int as spans_active,
    coalesce((
      select count(*) from public.span_attributions sa join active a on a.span_id=sa.span_id
      where a.generation=g.generation
    ),0)::int as attributions,
    coalesce((
      select count(*) from public.review_queue rq join active a on a.span_id=rq.span_id
      where a.generation=g.generation
    ),0)::int as review_queue
  from gens g
)
select generation, spans_active, attributions, review_queue
from counts_by_gen
order by generation asc;

\echo ''
\echo '=== COVERAGE OFFENDERS (first 25) ==='

with
params as (select :'interaction_id'::text as interaction_id),
active_spans_all as (
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
max_gen as (select coalesce(max(generation),0) as gen_max from active_spans_all),
active_spans as (select * from active_spans_all where generation=(select gen_max from max_gen)),
attrs as (select span_id, decision, needs_review, confidence from public.span_attributions),
rq as (select span_id, status from public.review_queue)
select
  s.span_id,
  s.span_index,
  s.char_start,
  s.char_end,
  case when a.span_id is null then false else true end as has_attribution,
  case when r.span_id is null then false else true end as has_review_item,
  a.decision,
  a.needs_review,
  a.confidence,
  r.status as review_status,
  case
    when a.span_id is null and r.span_id is null then 'UNCOVERED'
    when a.span_id is not null and r.span_id is not null then 'DOUBLE_COVERED'
    else 'OK'
  end as coverage_class
from active_spans s
left join attrs a on a.span_id = s.span_id
left join rq r on r.span_id = s.span_id
where (a.span_id is null and r.span_id is null)
   or (a.span_id is not null and r.span_id is not null)
order by s.span_index asc
limit 25;
