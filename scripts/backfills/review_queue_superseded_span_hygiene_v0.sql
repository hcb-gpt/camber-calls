-- review_queue_superseded_span_hygiene_v0
--
-- Purpose:
-- - Retarget pending review_queue rows that point at superseded spans to the current active span
--   for the same (interaction_id, span_index).
-- - Auto-dismiss rows that are duplicates (the active span already has a review_queue row)
--   or stale-covered (the active span already has an attribution).
--
-- Preconditions:
-- - coordinate with STRAT (this mutates review_queue)
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
--
-- Safety:
-- - constrained to status='pending' AND span_id points to conversation_spans.is_superseded=true
-- - preserves canonical uniqueness: review_queue has UNIQUE(span_id) where span_id is not null
-- - does not delete review_queue rows; only updates/dismisses/retargets

BEGIN;

WITH superseded_pending AS (
  SELECT
    rq.id AS review_queue_id,
    rq.interaction_id AS rq_interaction_id,
    rq.span_id AS old_span_id,
    cs.interaction_id AS span_interaction_id,
    cs.span_index AS span_index,
    cs.segment_generation AS old_segment_generation
  FROM public.review_queue rq
  JOIN public.conversation_spans cs ON cs.id = rq.span_id
  WHERE rq.status = 'pending'
    AND cs.is_superseded IS TRUE
),
with_replacement AS (
  SELECT
    sp.*,
    r.id AS new_span_id,
    r.segment_generation AS new_segment_generation
  FROM superseded_pending sp
  LEFT JOIN LATERAL (
    SELECT id, segment_generation
    FROM public.conversation_spans cs2
    WHERE cs2.interaction_id = sp.span_interaction_id
      AND cs2.span_index = sp.span_index
      AND cs2.is_superseded IS FALSE
    ORDER BY cs2.segment_generation DESC, cs2.id DESC
    LIMIT 1
  ) r ON TRUE
),
enriched AS (
  SELECT
    wr.*,
    (SELECT rq2.id FROM public.review_queue rq2 WHERE rq2.span_id = wr.new_span_id LIMIT 1) AS any_rq_id_on_new_span,
    EXISTS (SELECT 1 FROM public.span_attributions sa WHERE sa.span_id = wr.new_span_id LIMIT 1) AS new_span_has_any_attribution
  FROM with_replacement wr
),
actions AS (
  SELECT
    e.review_queue_id,
    e.rq_interaction_id,
    e.old_span_id,
    e.span_interaction_id,
    e.span_index,
    e.old_segment_generation,
    e.new_span_id,
    e.new_segment_generation,
    e.any_rq_id_on_new_span,
    e.new_span_has_any_attribution,
    CASE
      WHEN e.new_span_id IS NULL THEN 'dismiss_missing_replacement_span'
      WHEN e.any_rq_id_on_new_span IS NOT NULL THEN 'dismiss_duplicate_new_span_already_has_review_row'
      WHEN e.new_span_has_any_attribution IS TRUE THEN 'dismiss_stale_new_span_already_attributed'
      ELSE 'retarget_to_active_span'
    END AS action
  FROM enriched e
)
-- 1) Dismiss actions
UPDATE public.review_queue rq
SET
  status = 'dismissed',
  resolved_at = now(),
  resolved_by = 'DATA_BACKFILL',
  resolution_action = 'auto_dismiss',
  resolution_notes = CASE
    WHEN a.action = 'dismiss_missing_replacement_span' THEN
      format('[superseded_span_hygiene_v0] old_span_id=%s missing active replacement for interaction_id=%s span_index=%s',
        a.old_span_id, a.span_interaction_id, a.span_index)
    WHEN a.action = 'dismiss_duplicate_new_span_already_has_review_row' THEN
      format('[superseded_span_hygiene_v0] old_span_id=%s duplicate: active_span_id=%s already has review_queue row id=%s',
        a.old_span_id, a.new_span_id, a.any_rq_id_on_new_span)
    WHEN a.action = 'dismiss_stale_new_span_already_attributed' THEN
      format('[superseded_span_hygiene_v0] old_span_id=%s stale-covered: active_span_id=%s already has attribution',
        a.old_span_id, a.new_span_id)
    ELSE
      '[superseded_span_hygiene_v0] unspecified'
  END
FROM actions a
WHERE rq.id = a.review_queue_id
  AND a.action <> 'retarget_to_active_span';

-- 2) Retarget actions
UPDATE public.review_queue rq
SET
  span_id = a.new_span_id,
  interaction_id = coalesce(rq.interaction_id, a.span_interaction_id)
FROM actions a
WHERE rq.id = a.review_queue_id
  AND a.action = 'retarget_to_active_span';

-- Summary of what changed in this transaction (dismissed vs retargeted).
WITH recent AS (
  SELECT
    rq.id,
    rq.status,
    rq.resolution_action,
    rq.resolution_notes
  FROM public.review_queue rq
  WHERE (
    (rq.resolved_by = 'DATA_BACKFILL' AND rq.resolved_at >= (now() - interval '10 minutes')
      AND rq.resolution_notes LIKE '[superseded_span_hygiene_v0]%')
    OR (rq.updated_at >= (now() - interval '10 minutes'))
  )
)
SELECT
  CASE
    WHEN status = 'dismissed' THEN 'dismissed'
    ELSE 'retargeted_or_touched'
  END AS bucket,
  COUNT(*) AS n
FROM recent
GROUP BY 1
ORDER BY n DESC, bucket ASC;

COMMIT;

