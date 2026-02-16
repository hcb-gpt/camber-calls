-- NOT EXECUTED (proposal only) — mutating SQL to dismiss historical review-queue pollution from Sittler staff-name leak.
--
-- SAFETY PROPERTIES:
-- - Targets only: review_queue.status='pending' AND created_at < cutover AND latest ai-router project_id is Sittler*
-- - Excludes: any span_id that ever had attribution_lock='human'
-- - Excludes: spans where applied_project_id is non-null (data-quality cases should be handled via GT correction RPC)
-- - Reversible: copies the full pre-update state into a temp backup table; export it before updating.
--
-- *Sittler projects are selected by projects.name ILIKE '%Sittler%'. Narrow further if needed (e.g. '%Sittler%Madison%').

\set cutover_utc '2026-02-15T19:43:00Z'
\set sittler_name_pattern '%Sittler%'
\set resolved_by 'system:sittler_staff_name_leak_cleanup'

BEGIN;

-- 1) Identify targets and back up their current state (export this before updating).
CREATE TEMP TABLE _sittler_review_queue_backup AS
WITH
params AS (
  SELECT
    (:'cutover_utc')::timestamptz AS cutover_utc,
    (:'sittler_name_pattern')::text AS sittler_name_pattern
),
sittler_projects AS (
  SELECT p.id
  FROM public.projects p, params
  WHERE p.name ILIKE params.sittler_name_pattern
),
latest_sa AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.project_id,
    sa.applied_project_id,
    sa.decision,
    sa.attributed_at,
    sa.id AS span_attribution_id
  FROM public.span_attributions sa
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST, sa.id DESC
),
human_locked_spans AS (
  SELECT DISTINCT sa.span_id
  FROM public.span_attributions sa
  WHERE sa.attribution_lock = 'human'
)
SELECT
  rq.id AS review_queue_id,
  rq.status AS old_status,
  rq.resolved_at AS old_resolved_at,
  rq.resolved_by AS old_resolved_by,
  rq.resolution_action AS old_resolution_action,
  rq.resolution_notes AS old_resolution_notes,
  rq.created_at AS review_created_at,
  rq.interaction_id,
  rq.span_id,
  COALESCE(rq.reason_codes, rq.reasons) AS reason_codes,
  ls.project_id AS ai_project_id,
  ls.applied_project_id,
  ls.decision,
  ls.span_attribution_id
FROM public.review_queue rq
JOIN latest_sa ls
  ON ls.span_id = rq.span_id
WHERE
  rq.status = 'pending'
  AND rq.span_id IS NOT NULL
  AND rq.interaction_id NOT LIKE 'cll_SHADOW_%'
  AND rq.interaction_id NOT LIKE 'cll_ITEST_%'
  AND rq.created_at < (SELECT cutover_utc FROM params)
  AND ls.project_id IN (SELECT id FROM sittler_projects)
  AND ls.applied_project_id IS NULL
  AND COALESCE(ls.decision, 'unknown') IN ('review', 'none', 'unknown')
  AND rq.span_id NOT IN (SELECT span_id FROM human_locked_spans);

-- 2) Review target count before proceeding.
SELECT COUNT(*) AS target_rows FROM _sittler_review_queue_backup;

-- 3) Export backup before updating (example):
-- \copy _sittler_review_queue_backup TO 'sittler_review_queue_backup.csv' CSV HEADER

-- 4) Bulk-dismiss.
UPDATE public.review_queue rq
SET
  status = 'dismissed',
  resolved_at = now(),
  resolved_by = :'resolved_by',
  resolution_action = 'auto_dismiss',
  resolution_notes = trim(both ' ' from coalesce(rq.resolution_notes, '') || ' [sittler_staff_name_leak_cleanup]')
FROM _sittler_review_queue_backup b
WHERE rq.id = b.review_queue_id;

-- 5) Verify.
SELECT rq.status, rq.resolution_action, COUNT(*) AS rows
FROM public.review_queue rq
JOIN _sittler_review_queue_backup b ON b.review_queue_id = rq.id
GROUP BY 1, 2
ORDER BY rows DESC;

COMMIT;

-- Revert (requires the exported backup; do NOT rely on TEMP table post-session):
-- UPDATE public.review_queue rq
-- SET
--   status = b.old_status,
--   resolved_at = b.old_resolved_at,
--   resolved_by = b.old_resolved_by,
--   resolution_action = b.old_resolution_action,
--   resolution_notes = b.old_resolution_notes
-- FROM _sittler_review_queue_backup b
-- WHERE rq.id = b.review_queue_id;
