-- Entity Drift Dashboard: Weekly Snapshot Function
-- Per STRATA-25 Entity Drift Dashboard Spec v0.1 (P4: Weekly digest automation)

CREATE OR REPLACE FUNCTION capture_entity_drift_snapshot()
RETURNS JSONB AS $$
DECLARE
  v_date DATE := CURRENT_DATE;
  v_report JSONB;
BEGIN
  -- Delete existing snapshot for today (if re-running)
  DELETE FROM entity_drift_metrics WHERE snapshot_date = v_date;
  
  -- Capture role metrics
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_date,
    'contacts.role',
    COUNT(DISTINCT role),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT role) <= 15 THEN 100 WHEN COUNT(DISTINCT role) <= 20 THEN 50 ELSE 0 END,
    15,
    20,
    CASE WHEN COUNT(DISTINCT role) > 20 THEN 'RED' WHEN COUNT(DISTINCT role) > 15 THEN 'YELLOW' ELSE 'GREEN' END
  FROM contacts WHERE role IS NOT NULL;
  
  -- Capture trade metrics
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_date,
    'contacts.trade',
    COUNT(DISTINCT trade),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT trade) <= 80 THEN 100 WHEN COUNT(DISTINCT trade) <= 100 THEN 50 ELSE 0 END,
    80,
    100,
    CASE WHEN COUNT(DISTINCT trade) > 100 THEN 'RED' WHEN COUNT(DISTINCT trade) > 80 THEN 'YELLOW' ELSE 'GREEN' END
  FROM contacts WHERE trade IS NOT NULL;
  
  -- Capture contact_type metrics
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_date,
    'contacts.contact_type',
    COUNT(DISTINCT contact_type),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT contact_type) <= 10 THEN 100 ELSE 0 END,
    10,
    10,
    CASE WHEN COUNT(DISTINCT contact_type) > 10 THEN 'RED' ELSE 'GREEN' END
  FROM contacts WHERE contact_type IS NOT NULL;
  
  -- Capture phase metrics
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_date,
    'projects.phase',
    COUNT(DISTINCT phase),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT phase) <= 6 THEN 100 ELSE 0 END,
    6,
    6,
    CASE WHEN COUNT(DISTINCT phase) > 6 THEN 'RED' ELSE 'GREEN' END
  FROM projects WHERE phase IS NOT NULL;
  
  -- Capture claim_type metrics
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_date,
    'journal_claims.claim_type',
    COUNT(DISTINCT claim_type),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT claim_type) <= 10 THEN 100 ELSE 0 END,
    10,
    10,
    CASE WHEN COUNT(DISTINCT claim_type) > 10 THEN 'RED' ELSE 'GREEN' END
  FROM journal_claims;
  
  -- Build report
  SELECT jsonb_build_object(
    'snapshot_date', v_date,
    'overall_health', (SELECT AVG(health_score) FROM entity_drift_metrics WHERE snapshot_date = v_date),
    'fields', (SELECT jsonb_agg(row_to_json(e)) FROM entity_drift_metrics e WHERE snapshot_date = v_date),
    'alerts', (SELECT jsonb_agg(field_name) FROM entity_drift_metrics WHERE snapshot_date = v_date AND threshold_status != 'GREEN')
  ) INTO v_report;
  
  RETURN v_report;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION capture_entity_drift_snapshot IS 
'Captures weekly entity drift snapshot. Call every Monday via scheduler or manually.';;
