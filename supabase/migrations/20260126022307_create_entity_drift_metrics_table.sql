-- Entity Drift Dashboard: Metrics Storage
-- Per STRATA-25 Entity Drift Dashboard Spec v0.1

CREATE TABLE entity_drift_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_date DATE NOT NULL,
  field_name TEXT NOT NULL,
  unique_count INTEGER NOT NULL,
  new_values_count INTEGER NOT NULL,
  new_values JSONB,
  health_score INTEGER CHECK (health_score BETWEEN 0 AND 100),
  alert_threshold INTEGER,
  critical_threshold INTEGER,
  threshold_status TEXT CHECK (threshold_status IN ('GREEN', 'YELLOW', 'RED')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE (snapshot_date, field_name)
);

CREATE INDEX idx_drift_metrics_date ON entity_drift_metrics(snapshot_date);
CREATE INDEX idx_drift_metrics_field ON entity_drift_metrics(field_name);
CREATE INDEX idx_drift_metrics_status ON entity_drift_metrics(threshold_status);

COMMENT ON TABLE entity_drift_metrics IS 
'Weekly snapshots of entity field entropy for drift monitoring. Per STRATA-25 Entity Drift Dashboard Spec v0.1.';;
