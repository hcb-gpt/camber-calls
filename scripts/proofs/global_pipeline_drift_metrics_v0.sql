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
model_error_pending AS (
  SELECT *
  FROM rq_enriched
  WHERE 'model_error' = ANY(reason_codes)
),
latest_spans AS (
  SELECT DISTINCT ON (s.interaction_id, s.span_index)
    s.interaction_id,
    s.id AS span_id,
    s.segment_generation,
    s.span_index,
    s.is_superseded,
    s.char_start,
    s.char_end
  FROM public.conversation_spans s
  WHERE s.is_superseded = false
  ORDER BY s.interaction_id, s.span_index, s.segment_generation DESC
),
latest_attr AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.attributed_at,
    sa.decision,
    sa.needs_review
  FROM public.span_attributions sa
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST
),
latest_spans_missing_attr AS (
  SELECT
    ls.interaction_id,
    ls.span_id
  FROM latest_spans ls
  LEFT JOIN latest_attr la ON la.span_id = ls.span_id
  WHERE la.span_id IS NULL
),
oversize_spans AS (
  SELECT
    ls.interaction_id,
    ls.span_id,
    (ls.char_end - ls.char_start) AS span_chars
  FROM latest_spans ls
  WHERE (ls.char_end - ls.char_start) > 12000
)
SELECT
  now() AS measured_at_utc,
  (SELECT COUNT(*) FROM rq_pending) AS review_queue_pending_total,
  (SELECT COUNT(*) FROM rq_enriched WHERE span_id IS NULL) AS review_queue_pending_null_span,
  (SELECT COUNT(*) FROM rq_enriched WHERE span_id IS NOT NULL) AS review_queue_pending_with_span,
  (SELECT COUNT(*) FROM rq_enriched WHERE pending_invariant_bucket <> 'pending_ok') AS review_queue_pending_invariant_violations,
  (SELECT COUNT(*) FROM model_error_pending) AS review_queue_pending_model_error,
  (SELECT COUNT(*) FROM latest_spans_missing_attr) AS latest_spans_missing_attr,
  (SELECT COUNT(*) FROM oversize_spans) AS oversize_latest_spans_gt_12k_chars,
  (SELECT COUNT(*) FROM public.v_review_spans_missing_extraction) AS review_spans_missing_extraction
;

WITH rq_pending AS (
  SELECT
    rq.interaction_id,
    rq.span_id,
    coalesce(rq.reason_codes, rq.reasons) AS reason_codes,
    rq.created_at
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
),
model_error_pending AS (
  SELECT *
  FROM rq_pending
  WHERE 'model_error' = ANY(reason_codes)
)
SELECT
  interaction_id,
  COUNT(*) AS pending_model_error_rows,
  COUNT(*) FILTER (WHERE span_id IS NULL) AS null_span_rows,
  MIN(created_at) AS oldest_created_at,
  MAX(created_at) AS newest_created_at
FROM model_error_pending
GROUP BY 1
ORDER BY pending_model_error_rows DESC, newest_created_at DESC NULLS LAST, interaction_id ASC
LIMIT 30;

WITH rq_pending AS (
  SELECT
    rq.interaction_id,
    rq.span_id,
    rq.module,
    coalesce(rq.reason_codes, rq.reasons) AS reason_codes
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
)
SELECT
  module,
  rc AS reason_code,
  COUNT(*) AS row_count
FROM rq_pending, unnest(coalesce(reason_codes, ARRAY[]::text[])) AS rc
GROUP BY 1, 2
ORDER BY row_count DESC, module ASC, reason_code ASC
LIMIT 50;

