-- span_attributions_double_covered_gate_fix_v0
--
-- Purpose:
-- - Fix `ci_gate_no_double_covered` violations by ensuring spans with a pending review_queue row
--   do not have any span_attributions rows with needs_review=false.
--
-- Background:
-- - Gate logic (live): joins span_attributions where needs_review=false with review_queue pending.
-- - Some spans accumulate older `assign` attributions (needs_review=false) plus newer `review` attributions.
--   The older rows trip the gate even though the span is correctly routed to review.
--
-- Preconditions:
-- - coordinate with STRAT (this mutates span_attributions)
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
--
-- Safety:
-- - constrained to spans that currently have review_queue.status='pending' (active review workflow)
-- - updates only span_attributions.needs_review from false -> true
-- - does not delete any attribution rows

BEGIN;

WITH target_attr AS (
  SELECT
    sa.id AS span_attribution_id,
    sa.span_id,
    sa.project_id,
    sa.attributed_at,
    rq.id AS review_queue_id
  FROM public.review_queue rq
  JOIN public.conversation_spans cs ON cs.id = rq.span_id
  JOIN public.span_attributions sa ON sa.span_id = rq.span_id
  WHERE rq.status = 'pending'
    AND rq.span_id IS NOT NULL
    AND cs.is_superseded IS FALSE
    AND sa.needs_review IS FALSE
)
UPDATE public.span_attributions sa
SET needs_review = TRUE
FROM target_attr t
WHERE sa.id = t.span_attribution_id;

-- Summary of what changed in this transaction.
WITH updated AS (
  SELECT
    sa.span_id,
    COUNT(*) AS updated_rows
  FROM public.span_attributions sa
  WHERE sa.needs_review IS TRUE
    AND sa.attributed_at >= (now() - interval '10 minutes')
  GROUP BY 1
)
SELECT
  COUNT(*) AS spans_touched,
  COALESCE(SUM(updated_rows), 0) AS attribution_rows_updated
FROM updated;

COMMIT;

