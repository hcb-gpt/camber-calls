-- Scoreboard view for ongoing v3 vs v3.6 comparison
CREATE OR REPLACE VIEW v3_v36_scoreboard AS
WITH v3_stats AS (
  SELECT
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE v3_project_id IS NOT NULL) as has_project,
    COUNT(*) FILTER (WHERE v3_contact_id IS NOT NULL) as has_contact,
    COUNT(*) FILTER (WHERE v3_has_summary = true) as has_summary,
    COUNT(*) FILTER (WHERE v3_needs_review = true) as needs_review,
    ROUND(AVG(v3_confidence)::numeric, 3) as avg_confidence
  FROM v3_v36_comparison_set
),
v36_stats AS (
  SELECT
    COUNT(*) FILTER (WHERE v36_processed = true) as processed,
    COUNT(*) FILTER (WHERE v36_project_id IS NOT NULL) as has_project,
    COUNT(*) FILTER (WHERE v36_contact_id IS NOT NULL) as has_contact,
    COUNT(*) FILTER (WHERE v36_has_summary = true) as has_summary,
    COUNT(*) FILTER (WHERE v36_needs_review = true) as needs_review,
    ROUND(AVG(v36_confidence)::numeric, 3) as avg_confidence
  FROM v3_v36_comparison_set
  WHERE v36_processed = true
)
SELECT 
  'Coverage' as metric,
  v3.total::text as v3,
  COALESCE(v36.processed, 0)::text as v3_6,
  ROUND(100.0 * COALESCE(v36.processed, 0) / NULLIF(v3.total, 0), 1)::text || '%' as pct,
  CASE WHEN COALESCE(v36.processed, 0) >= v3.total THEN 'PASS' ELSE 'FAIL' END as status
FROM v3_stats v3, v36_stats v36

UNION ALL

SELECT 
  'Project Attribution',
  v3.has_project::text || '/' || v3.total::text,
  COALESCE(v36.has_project, 0)::text || '/' || COALESCE(v36.processed, 0)::text,
  CASE WHEN COALESCE(v36.processed, 0) > 0 
       THEN ROUND(100.0 * v36.has_project / v36.processed, 1)::text || '%'
       ELSE 'N/A' END,
  CASE WHEN COALESCE(v36.processed, 0) = 0 THEN 'NO_DATA'
       WHEN (1.0 * v36.has_project / v36.processed) >= (1.0 * v3.has_project / NULLIF(v3.total, 0)) THEN 'PASS'
       ELSE 'FAIL' END
FROM v3_stats v3, v36_stats v36

UNION ALL

SELECT 
  'Contact Resolution',
  v3.has_contact::text || '/' || v3.total::text,
  COALESCE(v36.has_contact, 0)::text || '/' || COALESCE(v36.processed, 0)::text,
  CASE WHEN COALESCE(v36.processed, 0) > 0 
       THEN ROUND(100.0 * v36.has_contact / v36.processed, 1)::text || '%'
       ELSE 'N/A' END,
  CASE WHEN COALESCE(v36.processed, 0) = 0 THEN 'NO_DATA'
       WHEN (1.0 * v36.has_contact / v36.processed) >= (1.0 * v3.has_contact / NULLIF(v3.total, 0)) THEN 'PASS'
       ELSE 'FAIL' END
FROM v3_stats v3, v36_stats v36

UNION ALL

SELECT 
  'Has Summary',
  v3.has_summary::text || '/' || v3.total::text,
  COALESCE(v36.has_summary, 0)::text || '/' || COALESCE(v36.processed, 0)::text,
  CASE WHEN COALESCE(v36.processed, 0) > 0 
       THEN ROUND(100.0 * v36.has_summary / v36.processed, 1)::text || '%'
       ELSE 'N/A' END,
  CASE WHEN COALESCE(v36.processed, 0) = 0 THEN 'NO_DATA'
       WHEN (1.0 * v36.has_summary / v36.processed) >= (1.0 * v3.has_summary / NULLIF(v3.total, 0)) THEN 'PASS'
       ELSE 'FAIL' END
FROM v3_stats v3, v36_stats v36

UNION ALL

SELECT 
  'Needs Review (lower=better)',
  v3.needs_review::text || '/' || v3.total::text,
  COALESCE(v36.needs_review, 0)::text || '/' || COALESCE(v36.processed, 0)::text,
  CASE WHEN COALESCE(v36.processed, 0) > 0 
       THEN ROUND(100.0 * v36.needs_review / v36.processed, 1)::text || '%'
       ELSE 'N/A' END,
  CASE WHEN COALESCE(v36.processed, 0) = 0 THEN 'NO_DATA'
       WHEN (1.0 * v36.needs_review / v36.processed) <= (1.0 * v3.needs_review / NULLIF(v3.total, 0)) THEN 'PASS'
       ELSE 'FAIL' END
FROM v3_stats v3, v36_stats v36

UNION ALL

SELECT 
  'Avg Confidence',
  v3.avg_confidence::text,
  COALESCE(v36.avg_confidence::text, 'N/A'),
  '-',
  CASE WHEN COALESCE(v36.processed, 0) = 0 THEN 'NO_DATA'
       WHEN v36.avg_confidence >= v3.avg_confidence THEN 'PASS'
       ELSE 'FAIL' END
FROM v3_stats v3, v36_stats v36;

COMMENT ON VIEW v3_v36_scoreboard IS 'Run SELECT * FROM v3_v36_scoreboard to see current v3 vs v3.6 comparison';;
