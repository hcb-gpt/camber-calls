-- Stopline2 DB validation inventory (read-only)
-- Run against production/staging DB for audit trail.

-- A) Views that read interactions.project_id
WITH view_reads AS (
  SELECT n.nspname, c.relname AS view_name
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'v'
    AND pg_get_viewdef(c.oid, true) ILIKE '%interactions.project_id%'
)
SELECT
  'VIEW_INTERACTIONS_PROJECT_ID' AS artifact_type,
  view_name
FROM view_reads
ORDER BY view_name;

-- B) Triggers that act on interactions and touch project_id
WITH trigger_reads AS (
  SELECT
    n.nspname,
    c.relname AS table_name,
    tg.tgname AS trigger_name,
    p.proname AS function_name
  FROM pg_trigger tg
  JOIN pg_class c ON c.oid = tg.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = tg.tgfoid
  WHERE NOT tg.tgisinternal
    AND c.relname = 'interactions'
    AND pg_get_functiondef(p.oid) ILIKE '%project_id%'
)
SELECT
  'INTERACTIONS_TRIGGER_ON_PROJECT_ID' AS artifact_type,
  trigger_name,
  function_name
FROM trigger_reads
ORDER BY trigger_name;

-- C) Journal* indexes that include call_id
SELECT
  'JOURNAL_INDEXES_CALL_ID' AS artifact_type,
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename LIKE 'journal_%'
  AND indexdef ILIKE '%call_id%'
ORDER BY tablename, indexname;

-- D) Call-vs-span parity checks
WITH span_summary AS (
  SELECT
    cs.interaction_id,
    COUNT(*) AS span_attr_rows,
    COUNT(*) FILTER (WHERE sa.project_id IS NOT NULL) AS span_attr_nonnull,
    COUNT(DISTINCT sa.project_id) FILTER (WHERE sa.project_id IS NOT NULL) AS distinct_projects
  FROM conversation_spans cs
  JOIN span_attributions sa ON sa.span_id = cs.id
  GROUP BY cs.interaction_id
),
call_scope AS (
  SELECT
    i.interaction_id,
    i.project_id,
    COALESCE(ss.span_attr_rows, 0) AS span_attr_rows,
    COALESCE(ss.distinct_projects, 0) AS distinct_projects,
    EXISTS (
      SELECT 1
      FROM conversation_spans cs2
      JOIN span_attributions sa2 ON sa2.span_id = cs2.id
      WHERE cs2.interaction_id = i.interaction_id
        AND sa2.project_id = i.project_id
    ) AS has_matching_span
  FROM interactions i
  LEFT JOIN span_summary ss ON ss.interaction_id = i.interaction_id
)
SELECT
  'PARITY_QUERY' AS artifact_type,
  metric,
  value
FROM (
  VALUES
    ('1_total_calls_project_attributed', (SELECT COUNT(*)::bigint FROM interactions i WHERE i.project_id IS NOT NULL)),
    ('2_calls_no_span_attribution', (SELECT COUNT(*)::bigint FROM call_scope cs WHERE cs.project_id IS NOT NULL AND cs.span_attr_rows = 0)),
    ('3_calls_with_matching_project_span', (SELECT COUNT(*)::bigint FROM call_scope cs WHERE cs.project_id IS NOT NULL AND cs.has_matching_span)),
    ('4_calls_project_set_no_matching_span', (SELECT COUNT(*)::bigint FROM call_scope cs WHERE cs.project_id IS NOT NULL AND NOT cs.has_matching_span AND cs.span_attr_rows > 0)),
    ('5_calls_with_multi_project_span_attr', (SELECT COUNT(*)::bigint FROM call_scope cs WHERE cs.project_id IS NOT NULL AND cs.distinct_projects > 1)),
    ('6_calls_with_multi_span_no_project', (SELECT COUNT(*)::bigint FROM call_scope cs WHERE cs.project_id IS NOT NULL AND cs.distinct_projects = 0 AND cs.span_attr_rows > 1))
) AS v(metric, value)
ORDER BY metric;

