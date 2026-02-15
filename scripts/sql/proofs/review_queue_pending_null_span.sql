-- Pending review items with missing span_id (often indicates upstream wiring gaps).
-- Run: scripts/query.sh --file scripts/sql/proofs/review_queue_pending_null_span.sql

select
  unnest(coalesce(rq.reason_codes, rq.reasons, array['(no_reason)'])) as reason_code,
  count(*) as pending_count
from public.review_queue rq
where rq.status = 'pending'
  and rq.span_id is null
group by 1
order by pending_count desc, reason_code asc
limit 100;

