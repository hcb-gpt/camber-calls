-- Weekly Entity Drift Snapshot Function
-- Per STRATA-25 Entity Drift Dashboard Spec v0.1

CREATE OR REPLACE FUNCTION capture_entity_drift_snapshot()
RETURNS JSONB AS $$
DECLARE
  v_snapshot_date DATE := CURRENT_DATE;
  v_results JSONB := '[]'::JSONB;
  v_field RECORD;
BEGIN
  -- Capture role entropy
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_snapshot_date,
    'contacts.role',
    COUNT(DISTINCT role),
    0, -- will compute new values separately
    NULL,
    CASE WHEN COUNT(DISTINCT role) <= 15 THEN 100 ELSE 50 END,
    120,
    150,
    CASE 
      WHEN COUNT(DISTINCT role) > 150 THEN 'CRITICAL'
      WHEN COUNT(DISTINCT role) > 120 THEN 'ALERT'
      ELSE 'OK'
    END
  FROM contacts WHERE role IS NOT NULL
  ON CONFLICT (snapshot_date, field_name) DO UPDATE SET
    unique_count = EXCLUDED.unique_count,
    health_score = EXCLUDED.health_score,
    threshold_status = EXCLUDED.threshold_status;

  -- Capture trade entropy
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_snapshot_date,
    'contacts.trade',
    COUNT(DISTINCT trade),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT trade) <= 80 THEN 100 ELSE 50 END,
    80,
    100,
    CASE 
      WHEN COUNT(DISTINCT trade) > 100 THEN 'CRITICAL'
      WHEN COUNT(DISTINCT trade) > 80 THEN 'ALERT'
      ELSE 'OK'
    END
  FROM contacts WHERE trade IS NOT NULL
  ON CONFLICT (snapshot_date, field_name) DO UPDATE SET
    unique_count = EXCLUDED.unique_count,
    health_score = EXCLUDED.health_score,
    threshold_status = EXCLUDED.threshold_status;

  -- Capture review_reasons entropy
  INSERT INTO entity_drift_metrics (snapshot_date, field_name, unique_count, new_values_count, new_values, health_score, alert_threshold, critical_threshold, threshold_status)
  SELECT 
    v_snapshot_date,
    'interactions.review_reasons',
    COUNT(DISTINCT reason_val),
    0,
    NULL,
    CASE WHEN COUNT(DISTINCT reason_val) <= 500 THEN 100 ELSE 50 END,
    500,
    600,
    CASE 
      WHEN COUNT(DISTINCT reason_val) > 600 THEN 'CRITICAL'
      WHEN COUNT(DISTINCT reason_val) > 500 THEN 'ALERT'
      ELSE 'OK'
    END
  FROM (SELECT unnest(review_reasons) AS reason_val FROM interactions WHERE review_reasons IS NOT NULL) r
  ON CONFLICT (snapshot_date, field_name) DO UPDATE SET
    unique_count = EXCLUDED.unique_count,
    health_score = EXCLUDED.health_score,
    threshold_status = EXCLUDED.threshold_status;

  -- Return summary
  SELECT jsonb_agg(row_to_json(m)) INTO v_results
  FROM entity_drift_metrics m
  WHERE snapshot_date = v_snapshot_date;

  RETURN jsonb_build_object(
    'snapshot_date', v_snapshot_date,
    'fields_captured', jsonb_array_length(v_results),
    'metrics', v_results
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION capture_entity_drift_snapshot IS 
'Captures weekly entity drift snapshot. Run every Monday via cron/scheduler.';;
