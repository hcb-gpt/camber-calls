-- Finds pending review items pointing at superseded spans (stale review rows).
-- Run: scripts/query.sh --file scripts/sql/proofs/review_queue_pending_on_superseded_span.sql

select
  rq.id as review_queue_id,
  rq.created_at,
  rq.interaction_id,
  rq.span_id,
  cs.segment_generation,
  cs.span_index,
  cs.superseded_at,
  rq.status,
  coalesce(rq.reason_codes, rq.reasons) as reason_codes
from public.review_queue rq
join public.conversation_spans cs on cs.id = rq.span_id
where
  rq.status = 'pending'
  and cs.is_superseded = true
order by rq.created_at desc
limit 200;

