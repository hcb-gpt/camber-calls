
-- ================================================
-- DAILY OPS QUERY PACK
-- ================================================

-- 1. Last 10 repair sources
CREATE OR REPLACE VIEW v_repair_last_10_sources AS
SELECT 
  source,
  COUNT(*) as repairs_count,
  MIN(processed_at) as first_at,
  MAX(processed_at) as last_at
FROM repair_payloads
WHERE status = 'completed'
  AND processed_at >= now() - interval '7 days'
GROUP BY source
ORDER BY MAX(processed_at) DESC
LIMIT 10;

-- 2. Repair failures (non-completed)
CREATE OR REPLACE VIEW v_repair_failures AS
SELECT 
  interaction_id,
  source,
  status,
  inserted_at,
  error_message
FROM repair_payloads
WHERE status NOT IN ('completed', 'pending')
ORDER BY inserted_at DESC;

-- 3. Zapier lineage coverage
CREATE OR REPLACE VIEW v_calls_raw_zapier_lineage AS
SELECT 
  CASE WHEN zap_id IS NOT NULL THEN 'has_zap_id' ELSE 'no_zap_id' END as lineage,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct
FROM calls_raw
GROUP BY 1;

-- 4. Daily ops dashboard (combined)
CREATE OR REPLACE VIEW v_daily_ops_dashboard AS
SELECT 'backlog_total' as metric, COUNT(*)::text as value
FROM v_calls_raw_phone_backlog
UNION ALL
SELECT 'backlog_tier_a', COUNT(*)::text 
FROM v_calls_raw_phone_backlog WHERE repair_priority = 'A_high_confidence'
UNION ALL
SELECT 'backlog_tier_b', COUNT(*)::text 
FROM v_calls_raw_phone_backlog WHERE repair_priority = 'B_medium_confidence'
UNION ALL
SELECT 'backlog_tier_c', COUNT(*)::text 
FROM v_calls_raw_phone_backlog WHERE repair_priority = 'C_needs_external_lookup'
UNION ALL
SELECT 'repairs_today', COUNT(*)::text 
FROM repair_payloads WHERE status = 'completed' AND processed_at::date = CURRENT_DATE
UNION ALL
SELECT 'repairs_failed', COUNT(*)::text 
FROM repair_payloads WHERE status NOT IN ('completed', 'pending')
UNION ALL
SELECT 'calls_raw_total', COUNT(*)::text FROM calls_raw
UNION ALL
SELECT 'calls_raw_with_phone', COUNT(*)::text FROM calls_raw WHERE other_party_phone IS NOT NULL
UNION ALL
SELECT 'calls_raw_with_zap_id', COUNT(*)::text FROM calls_raw WHERE zap_id IS NOT NULL
UNION ALL
SELECT 'phone_coverage_pct', ROUND(100.0 * COUNT(other_party_phone) / COUNT(*), 1)::text FROM calls_raw
UNION ALL
SELECT 'zapier_lineage_pct', ROUND(100.0 * COUNT(zap_id) / COUNT(*), 1)::text FROM calls_raw;
;
