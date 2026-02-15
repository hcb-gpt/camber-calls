-- review_queue_noise_cleanup_v0
--
-- Purpose: reduce pending NULL-span review_queue noise by:
-- - auto-dismissing synthetic/test items (shadow/test_batch)
-- - auto-resolving stale items where the interaction is already resolved or needs_review=false
-- - auto-dismissing rows with missing interaction row
--
-- Preconditions:
-- - coordinate with STRAT (this mutates review_queue)
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
--
-- Safety:
-- - constrained to status='pending' AND span_id IS NULL (interaction-level queue only)
-- - does not delete rows

BEGIN;

WITH latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.is_shadow,
    cr.test_batch,
    (cr.raw_snapshot_json->'signal'->'raw_event'->>'test_batch') AS signal_test_batch
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
latest_interaction AS (
  SELECT DISTINCT ON (i.interaction_id)
    i.interaction_id,
    i.contact_id,
    i.project_id,
    i.needs_review
  FROM public.interactions i
  ORDER BY
    i.interaction_id,
    i.event_at_utc DESC NULLS LAST,
    i.ingested_at_utc DESC NULLS LAST,
    i.id DESC
),
targets AS (
  SELECT
    rq.id AS review_queue_id,
    rq.interaction_id,
    rq.module,
    lc.is_shadow,
    lc.test_batch,
    lc.signal_test_batch,
    li.interaction_id AS interaction_row_present,
    li.contact_id,
    li.project_id,
    li.needs_review,
    CASE
      WHEN
        lc.is_shadow IS TRUE
        OR lc.test_batch IS NOT NULL
        OR lc.signal_test_batch IS NOT NULL
        OR rq.interaction_id ~ '^cll_(DEV|AUTH|SUMMTEST|ITEST|SHADOW|TEST)'
        OR rq.interaction_id ~ 'TEST'
      THEN 'dismiss_synthetic_test'
      WHEN li.interaction_id IS NULL THEN 'dismiss_missing_interaction_row'
      WHEN li.needs_review IS FALSE OR (li.contact_id IS NOT NULL AND li.project_id IS NOT NULL) THEN 'resolve_stale_already_resolved'
      ELSE NULL
    END AS action
  FROM public.review_queue rq
  LEFT JOIN latest_call lc ON lc.call_id = rq.interaction_id
  LEFT JOIN latest_interaction li ON li.interaction_id = rq.interaction_id
  WHERE rq.status = 'pending'
    AND rq.span_id IS NULL
)
UPDATE public.review_queue rq
SET
  status = CASE
    WHEN t.action = 'resolve_stale_already_resolved' THEN 'resolved'
    ELSE 'dismissed'
  END,
  resolved_at = now(),
  resolved_by = 'DATA_BACKFILL',
  resolution_action = CASE
    WHEN t.action = 'resolve_stale_already_resolved' THEN 'auto_resolve'
    ELSE 'auto_dismiss'
  END,
  resolution_notes = CASE
    WHEN t.action = 'dismiss_synthetic_test' THEN '[noise_cleanup_v0] synthetic/test interaction (shadow/test_batch)'
    WHEN t.action = 'dismiss_missing_interaction_row' THEN '[noise_cleanup_v0] missing interactions row for interaction_id'
    WHEN t.action = 'resolve_stale_already_resolved' THEN '[noise_cleanup_v0] interaction already resolved or needs_review=false'
    ELSE '[noise_cleanup_v0] unspecified'
  END
FROM targets t
WHERE rq.id = t.review_queue_id
  AND t.action IS NOT NULL;

-- Summary of what changed in this transaction:
SELECT
  status,
  resolution_action,
  COUNT(*) AS n
FROM public.review_queue
WHERE resolved_by = 'DATA_BACKFILL'
  AND resolved_at >= (now() - interval '10 minutes')
GROUP BY 1, 2
ORDER BY 3 DESC, 1 ASC, 2 ASC;

COMMIT;
