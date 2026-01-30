-- Entity Drift Dashboard: KPI Views
-- Per STRATA-25 Entity Drift Dashboard Spec v0.1

-- 1. Role Entropy View
CREATE OR REPLACE VIEW entity_drift_role_entropy AS
SELECT 
  'contacts.role' AS field_name,
  role AS value,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM contacts
WHERE role IS NOT NULL
GROUP BY role
ORDER BY count DESC;

-- 2. Trade Entropy View
CREATE OR REPLACE VIEW entity_drift_trade_entropy AS
SELECT 
  'contacts.trade' AS field_name,
  trade AS value,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM contacts
WHERE trade IS NOT NULL
GROUP BY trade
ORDER BY count DESC;

-- 3. Review Reasons Entropy View
CREATE OR REPLACE VIEW entity_drift_review_reasons_entropy AS
SELECT 
  'review_queue.reasons' AS field_name,
  reason AS value,
  COUNT(*) AS count
FROM (
  SELECT unnest(review_reasons) AS reason 
  FROM interactions 
  WHERE review_reasons IS NOT NULL
) t
GROUP BY reason
ORDER BY count DESC;

-- 4. Contact Type Enum Check
CREATE OR REPLACE VIEW entity_drift_contact_type_violations AS
SELECT 
  'contacts.contact_type' AS field_name,
  contact_type AS value,
  COUNT(*) AS count,
  CASE 
    WHEN contact_type IN ('subcontractor', 'supplier', 'professional', 'client',
                          'government', 'internal', 'personal', 'other', 'spam', 'vendor')
    THEN 'VALID'
    ELSE 'VIOLATION'
  END AS status
FROM contacts
WHERE contact_type IS NOT NULL
GROUP BY contact_type
ORDER BY count DESC;

-- 5. Claim Type Alignment View
CREATE OR REPLACE VIEW entity_drift_claim_type_alignment AS
SELECT 
  'journal_claims.claim_type' AS source_field,
  claim_type AS source_value,
  COUNT(*) AS count,
  CASE claim_type
    WHEN 'fact' THEN 'state'
    WHEN 'update' THEN 'state'
    WHEN 'commitment' THEN 'commitment'
    WHEN 'decision' THEN 'decision'
    WHEN 'requirement' THEN 'request'
    WHEN 'concern' THEN 'risk'
    WHEN 'blocker' THEN 'open_loop'
    WHEN 'question' THEN 'open_loop'
    WHEN 'deadline' THEN 'commitment'
    WHEN 'preference' THEN '(no promotion)'
    ELSE 'UNKNOWN'
  END AS target_belief_type
FROM journal_claims
GROUP BY claim_type
ORDER BY count DESC;

-- 6. New Values This Week View
CREATE OR REPLACE VIEW entity_drift_new_values_week AS
WITH role_new AS (
  SELECT 'contacts.role' AS field_name, role AS new_value, COUNT(*) AS count
  FROM contacts
  WHERE created_at >= NOW() - INTERVAL '7 days'
    AND role NOT IN (
      SELECT DISTINCT role FROM contacts 
      WHERE created_at < NOW() - INTERVAL '7 days' AND role IS NOT NULL
    )
    AND role IS NOT NULL
  GROUP BY role
),
trade_new AS (
  SELECT 'contacts.trade' AS field_name, trade AS new_value, COUNT(*) AS count
  FROM contacts
  WHERE created_at >= NOW() - INTERVAL '7 days'
    AND trade NOT IN (
      SELECT DISTINCT trade FROM contacts 
      WHERE created_at < NOW() - INTERVAL '7 days' AND trade IS NOT NULL
    )
    AND trade IS NOT NULL
  GROUP BY trade
)
SELECT * FROM role_new
UNION ALL
SELECT * FROM trade_new
ORDER BY field_name, count DESC;

-- 7. Alias Candidate Detection View
CREATE OR REPLACE VIEW entity_drift_alias_candidates AS
SELECT DISTINCT 
  'contacts.role' AS field_name,
  a.role AS value_a, 
  b.role AS value_b,
  'case_variant' AS alias_type
FROM contacts a, contacts b
WHERE LOWER(a.role) = LOWER(b.role)
  AND a.role != b.role
  AND a.role IS NOT NULL;

-- 8. Summary Dashboard View
CREATE OR REPLACE VIEW entity_drift_summary AS
SELECT 
  field_name,
  unique_count,
  alert_threshold,
  critical_threshold,
  CASE 
    WHEN unique_count > critical_threshold THEN 'RED'
    WHEN unique_count > alert_threshold THEN 'YELLOW'
    ELSE 'GREEN'
  END AS status,
  CASE 
    WHEN unique_count > critical_threshold THEN 0
    WHEN unique_count > alert_threshold THEN 50
    ELSE 100
  END AS health_score
FROM (VALUES
  ('contacts.role', (SELECT COUNT(DISTINCT role) FROM contacts), 120, 150),
  ('contacts.trade', (SELECT COUNT(DISTINCT trade) FROM contacts), 80, 100),
  ('contacts.contact_type', (SELECT COUNT(DISTINCT contact_type) FROM contacts), 10, 10),
  ('journal_claims.claim_type', (SELECT COUNT(DISTINCT claim_type) FROM journal_claims), 10, 10),
  ('projects.phase', (SELECT COUNT(DISTINCT phase) FROM projects), 6, 6)
) AS t(field_name, unique_count, alert_threshold, critical_threshold);

COMMENT ON VIEW entity_drift_summary IS 
'Summary dashboard for entity drift monitoring. Shows health status for each monitored field.';;
