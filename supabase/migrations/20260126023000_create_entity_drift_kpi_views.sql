-- Entity Drift KPI Views
-- Per STRATA-25 Entity Drift Dashboard Spec v0.1

-- 1. Role Entropy View
CREATE OR REPLACE VIEW kpi_role_entropy AS
SELECT 
  'contacts.role' AS field_name,
  COUNT(DISTINCT role) AS unique_count,
  120 AS alert_threshold,
  150 AS critical_threshold,
  CASE 
    WHEN COUNT(DISTINCT role) > 150 THEN 'CRITICAL'
    WHEN COUNT(DISTINCT role) > 120 THEN 'ALERT'
    ELSE 'OK'
  END AS status
FROM contacts
WHERE role IS NOT NULL;

-- 2. Trade Entropy View
CREATE OR REPLACE VIEW kpi_trade_entropy AS
SELECT 
  'contacts.trade' AS field_name,
  COUNT(DISTINCT trade) AS unique_count,
  80 AS alert_threshold,
  100 AS critical_threshold,
  CASE 
    WHEN COUNT(DISTINCT trade) > 100 THEN 'CRITICAL'
    WHEN COUNT(DISTINCT trade) > 80 THEN 'ALERT'
    ELSE 'OK'
  END AS status
FROM contacts
WHERE trade IS NOT NULL;

-- 3. Review Reasons Entropy View
CREATE OR REPLACE VIEW kpi_review_reasons_entropy AS
SELECT 
  'review_queue.reasons' AS field_name,
  COUNT(DISTINCT reason_val) AS unique_count,
  500 AS alert_threshold,
  600 AS critical_threshold,
  CASE 
    WHEN COUNT(DISTINCT reason_val) > 600 THEN 'CRITICAL'
    WHEN COUNT(DISTINCT reason_val) > 500 THEN 'ALERT'
    ELSE 'OK'
  END AS status
FROM (
  SELECT unnest(review_reasons) AS reason_val 
  FROM interactions 
  WHERE review_reasons IS NOT NULL
) reasons;

-- 4. New Roles This Week View
CREATE OR REPLACE VIEW kpi_new_roles_this_week AS
SELECT role, COUNT(*) as contact_count
FROM contacts
WHERE created_at >= NOW() - INTERVAL '7 days'
  AND role IS NOT NULL
  AND role NOT IN (
    SELECT DISTINCT role FROM contacts
    WHERE created_at < NOW() - INTERVAL '7 days'
    AND role IS NOT NULL
  )
GROUP BY role
ORDER BY contact_count DESC;

-- 5. STRICT ENUM Violation Check for contact_type
CREATE OR REPLACE VIEW kpi_contact_type_violations AS
SELECT contact_type, COUNT(*) as count
FROM contacts
WHERE contact_type NOT IN (
  'subcontractor', 'supplier', 'professional', 'client',
  'government', 'internal', 'personal', 'other', 'spam', 'vendor'
)
AND contact_type IS NOT NULL
GROUP BY contact_type;

-- 6. Alias Candidate Detection (case variants)
CREATE OR REPLACE VIEW kpi_role_alias_candidates AS
SELECT DISTINCT a.role as value_a, b.role as value_b, COUNT(*) as pair_count
FROM contacts a
JOIN contacts b ON LOWER(a.role) = LOWER(b.role) AND a.role != b.role
WHERE a.role IS NOT NULL AND b.role IS NOT NULL
GROUP BY a.role, b.role
ORDER BY pair_count DESC;

-- 7. Combined Dashboard Summary View
CREATE OR REPLACE VIEW entity_drift_dashboard AS
SELECT 
  field_name,
  unique_count,
  alert_threshold,
  critical_threshold,
  status,
  CASE 
    WHEN status = 'OK' THEN 100
    WHEN status = 'ALERT' THEN 50
    WHEN status = 'CRITICAL' THEN 0
  END AS health_score
FROM (
  SELECT * FROM kpi_role_entropy
  UNION ALL
  SELECT * FROM kpi_trade_entropy
  UNION ALL
  SELECT * FROM kpi_review_reasons_entropy
) combined;

COMMENT ON VIEW entity_drift_dashboard IS 
'Combined entity drift KPIs for dashboard display. Per STRATA-25 spec v0.1.';;
