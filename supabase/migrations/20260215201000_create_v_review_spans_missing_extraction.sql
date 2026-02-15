-- Review-span extraction gap view
-- This view exposes review spans that are strong enough (confidence >= 0.70),
-- currently at review-gate, and not yet written into journal_claims.

CREATE OR REPLACE VIEW public.v_review_spans_missing_extraction AS
WITH latest_attribution AS (
  SELECT DISTINCT ON (span_id)
    span_id,
    decision,
    confidence,
    project_id,
    applied_project_id,
    COALESCE(project_id, applied_project_id) AS candidate_project_id,
    attributed_at
  FROM public.span_attributions
  ORDER BY span_id, attributed_at DESC
)
SELECT
  cs.interaction_id,
  cs.id AS span_id,
  cs.span_index,
  sa.decision,
  sa.confidence,
  sa.project_id,
  sa.applied_project_id,
  sa.attributed_at
FROM public.conversation_spans cs
JOIN latest_attribution sa
  ON sa.span_id = cs.id
WHERE
  cs.is_superseded = false
  AND sa.decision = 'review'
  AND sa.confidence >= 0.70
  AND sa.candidate_project_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.journal_claims jc
    WHERE jc.source_span_id = cs.id
      AND jc.active = true
  )
  AND EXISTS (
    SELECT 1
    FROM public.review_queue rq
    WHERE rq.span_id = cs.id
      AND rq.status = 'pending'
  )
ORDER BY sa.attributed_at DESC;
