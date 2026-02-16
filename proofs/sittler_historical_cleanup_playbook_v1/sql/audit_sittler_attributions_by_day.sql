-- Audit: Sittler attributions by day (UTC)
-- Buckets counts by decision (assign/review/none) and by pre/post cutover.
--
-- Run (read-only):
--   scripts/query.sh --file proofs/sittler_historical_cleanup_playbook_v1/sql/audit_sittler_attributions_by_day.sql

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
sittler_attributions AS (
  SELECT
    sa.id AS span_attribution_id,
    sa.span_id,
    sa.project_id,
    sa.applied_project_id,
    sa.decision,
    sa.needs_review,
    sa.attributed_at
  FROM public.span_attributions sa
  WHERE
    sa.project_id IN (SELECT id FROM sittler_projects)
    OR sa.applied_project_id IN (SELECT id FROM sittler_projects)
)
SELECT
  date_trunc('day', sa.attributed_at) AS day_utc,
  CASE
    WHEN sa.attributed_at < (SELECT cutover_utc FROM params) THEN 'pre_cutover'
    ELSE 'post_cutover'
  END AS cutover_bucket,
  COALESCE(sa.decision, 'unknown') AS decision,
  COUNT(*) AS attribution_rows,
  COUNT(DISTINCT sa.span_id) AS distinct_spans,
  COUNT(*) FILTER (WHERE sa.needs_review = true) AS needs_review_rows
FROM sittler_attributions sa
GROUP BY 1, 2, 3
ORDER BY day_utc DESC, cutover_bucket, decision;

