-- review_queue_span_hygiene_metrics_v0 (read-only)
--
-- Purpose: before/after proof helper for span-related review_queue hygiene.
-- Run with:
--   scripts/query.sh --file scripts/proofs/review_queue_span_hygiene_metrics_v0.sql

WITH rq_pending AS (
  SELECT
    rq.id,
    rq.interaction_id,
    rq.span_id,
    rq.status,
    rq.module,
    coalesce(rq.reason_codes, rq.reasons) AS reason_codes,
    rq.created_at
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
),
rq_enriched AS (
  SELECT
    rq.*,
    cs.interaction_id AS span_interaction_id,
    cs.is_superseded,
    CASE
      WHEN rq.span_id IS NULL THEN 'pending_null_span'
      WHEN cs.id IS NULL THEN 'pending_missing_span_row'
      WHEN cs.is_superseded IS TRUE THEN 'pending_on_superseded_span'
      WHEN cs.interaction_id IS NOT NULL AND rq.interaction_id IS NOT NULL AND cs.interaction_id <> rq.interaction_id THEN 'pending_span_interaction_mismatch'
      ELSE 'pending_ok'
    END AS pending_invariant_bucket
  FROM rq_pending rq
  LEFT JOIN public.conversation_spans cs ON cs.id = rq.span_id
),
double_covered_gate_violations AS (
  SELECT DISTINCT rq.span_id
  FROM public.review_queue rq
  JOIN public.conversation_spans cs ON cs.id = rq.span_id
  JOIN public.span_attributions sa ON sa.span_id = rq.span_id
  WHERE rq.status = 'pending'
    AND rq.span_id IS NOT NULL
    AND cs.is_superseded IS FALSE
    AND sa.needs_review IS FALSE
)
SELECT
  now() AS measured_at_utc,
  (SELECT COUNT(*) FROM rq_pending) AS review_queue_pending_total,
  (SELECT COUNT(*) FROM rq_enriched WHERE pending_invariant_bucket = 'pending_on_superseded_span') AS pending_on_superseded_span,
  (SELECT COUNT(DISTINCT interaction_id) FROM rq_enriched WHERE pending_invariant_bucket = 'pending_on_superseded_span') AS interactions_with_pending_on_superseded_span,
  (SELECT COUNT(*) FROM rq_enriched WHERE pending_invariant_bucket = 'pending_null_span') AS pending_null_span,
  (SELECT COUNT(*) FROM double_covered_gate_violations) AS pending_double_covered_gate_violations
;

-- Sample of double-covered gate violations (span_attributions.needs_review=false + review_queue pending).
SELECT
  cs.interaction_id,
  rq.span_id,
  sa.project_id,
  sa.attributed_at,
  sa.decision,
  sa.needs_review,
  rq.id AS review_queue_id,
  rq.created_at AS review_created_at
FROM public.review_queue rq
JOIN public.conversation_spans cs ON cs.id = rq.span_id
JOIN public.span_attributions sa ON sa.span_id = rq.span_id
WHERE rq.status = 'pending'
  AND rq.span_id IS NOT NULL
  AND cs.is_superseded IS FALSE
  AND sa.needs_review IS FALSE
ORDER BY sa.attributed_at DESC NULLS LAST
LIMIT 20;

-- Top interactions for pending_on_superseded_span
WITH rq_enriched AS (
  SELECT
    rq.interaction_id,
    rq.span_id,
    cs.interaction_id AS span_interaction_id,
    cs.is_superseded,
    cs.segment_generation,
    cs.span_index,
    rq.created_at
  FROM public.review_queue rq
  JOIN public.conversation_spans cs ON cs.id = rq.span_id
  WHERE rq.status = 'pending'
    AND cs.is_superseded IS TRUE
)
SELECT
  span_interaction_id AS interaction_id,
  COUNT(*) AS pending_on_superseded_rows,
  MIN(created_at) AS oldest_created_at,
  MAX(created_at) AS newest_created_at
FROM rq_enriched
GROUP BY 1
ORDER BY pending_on_superseded_rows DESC, newest_created_at DESC NULLS LAST, interaction_id ASC
LIMIT 20;
