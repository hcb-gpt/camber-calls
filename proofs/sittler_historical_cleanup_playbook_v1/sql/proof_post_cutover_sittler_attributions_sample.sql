-- Proof: any post-cutover Sittler attributions (should be 0 rows)
-- If nonzero, includes debug fields to root-cause the leakage source.
--
-- Run (read-only):
--   scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/proof_post_cutover_sittler_attributions_sample.sql

\set cutover_utc '2026-02-15T19:43:00Z'
\set sittler_name_pattern '%Sittler%'

WITH
params AS (
  SELECT
    (:'cutover_utc')::timestamptz AS cutover_utc,
    (:'sittler_name_pattern')::text AS sittler_name_pattern
),
sittler_projects AS (
  SELECT p.id, p.name
  FROM public.projects p, params
  WHERE p.name ILIKE params.sittler_name_pattern
),
post_cutover AS (
  SELECT
    sa.attributed_at,
    sa.span_id,
    sa.project_id,
    sa.applied_project_id,
    sa.decision,
    sa.confidence,
    sa.attributed_by,
    sa.attribution_lock,
    sa.needs_review,
    sa.prompt_version,
    sa.model_id,
    cs.interaction_id,
    cs.segmenter_version,
    cs.segment_generation
  FROM public.span_attributions sa
  JOIN public.conversation_spans cs
    ON cs.id = sa.span_id
  WHERE
    sa.attributed_at >= (SELECT cutover_utc FROM params)
    AND (
      sa.project_id IN (SELECT id FROM sittler_projects)
      OR sa.applied_project_id IN (SELECT id FROM sittler_projects)
    )
)
SELECT
  pc.attributed_at,
  pc.interaction_id,
  i.event_at_utc,
  pc.span_id,
  pc.segment_generation,
  pc.segmenter_version,
  pc.decision,
  pc.confidence,
  p_pred.name AS predicted_project,
  p_app.name AS applied_project,
  pc.attributed_by,
  pc.attribution_lock,
  pc.needs_review,
  pc.prompt_version,
  pc.model_id
FROM post_cutover pc
LEFT JOIN public.projects p_pred
  ON p_pred.id = pc.project_id
LEFT JOIN public.projects p_app
  ON p_app.id = pc.applied_project_id
LEFT JOIN public.interactions i
  ON i.interaction_id = pc.interaction_id
ORDER BY pc.attributed_at DESC
LIMIT 200;

