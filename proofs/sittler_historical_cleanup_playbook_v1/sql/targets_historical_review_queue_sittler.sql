-- Read-only target selection for historical review-queue pollution caused by Sittler staff-name leak.
-- Returns pending review_queue rows where the latest ai-router span_attributions predicts a Sittler project
-- (and is NOT applied), excluding any spans with a human lock.
--
-- Run (read-only):
--   scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/targets_historical_review_queue_sittler.sql

\set cutover_utc '2026-02-15T19:43:00Z'
\set sittler_name_pattern '%Sittler%'
\set limit_rows '200'

WITH
params AS (
  SELECT
    (:'cutover_utc')::timestamptz AS cutover_utc,
    (:'sittler_name_pattern')::text AS sittler_name_pattern,
    (:'limit_rows')::int AS limit_rows
),
sittler_projects AS (
  SELECT p.id, p.name
  FROM public.projects p, params
  WHERE p.name ILIKE params.sittler_name_pattern
),
latest_sa AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.project_id,
    sa.applied_project_id,
    sa.confidence,
    sa.decision,
    sa.attribution_lock,
    sa.needs_review,
    sa.prompt_version,
    sa.model_id,
    sa.attributed_by,
    sa.attributed_at,
    sa.id AS span_attribution_id
  FROM public.span_attributions sa
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST, sa.id DESC
),
human_locked_spans AS (
  SELECT DISTINCT sa.span_id
  FROM public.span_attributions sa
  WHERE sa.attribution_lock = 'human'
),
targets AS (
  SELECT
    rq.id AS review_queue_id,
    rq.status,
    rq.created_at,
    rq.interaction_id,
    rq.span_id,
    COALESCE(rq.reason_codes, rq.reasons) AS reason_codes,

    ls.project_id AS ai_project_id,
    p_ai.name AS ai_project_name,
    ls.applied_project_id,
    p_app.name AS applied_project_name,
    ls.confidence AS ai_confidence,
    ls.decision,
    ls.needs_review,

    ls.attributed_at AS attribution_at_utc,
    ls.attributed_by,
    ls.prompt_version,
    ls.model_id,
    ls.attribution_lock,

    cs.segment_generation,
    cs.segmenter_version
  FROM public.review_queue rq
  JOIN latest_sa ls
    ON ls.span_id = rq.span_id
  LEFT JOIN public.projects p_ai
    ON p_ai.id = ls.project_id
  LEFT JOIN public.projects p_app
    ON p_app.id = ls.applied_project_id
  LEFT JOIN public.conversation_spans cs
    ON cs.id = rq.span_id
  WHERE
    rq.status = 'pending'
    AND rq.span_id IS NOT NULL
    AND rq.interaction_id NOT LIKE 'cll_SHADOW_%'
    AND rq.interaction_id NOT LIKE 'cll_ITEST_%'
    AND rq.created_at < (SELECT cutover_utc FROM params)
    AND ls.project_id IN (SELECT id FROM sittler_projects)
    AND ls.applied_project_id IS NULL
    AND COALESCE(ls.decision, 'unknown') IN ('review', 'none', 'unknown')
    AND rq.span_id NOT IN (SELECT span_id FROM human_locked_spans)
)
SELECT
  t.*,
  COUNT(*) OVER () AS total_target_rows
FROM targets t
ORDER BY created_at DESC
LIMIT (SELECT limit_rows FROM params);
