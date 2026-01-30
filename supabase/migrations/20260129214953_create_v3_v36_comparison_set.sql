-- Comparison set: v3 interactions from last 7 days
-- This is the baseline against which v3.6 must prove superiority

CREATE TABLE IF NOT EXISTS v3_v36_comparison_set (
  id SERIAL PRIMARY KEY,
  interaction_id TEXT UNIQUE NOT NULL,
  channel TEXT,
  event_at_utc TIMESTAMPTZ,
  ingested_at_utc TIMESTAMPTZ,
  -- v3 outputs
  v3_project_id UUID,
  v3_contact_id UUID,
  v3_confidence NUMERIC,
  v3_has_summary BOOLEAN,
  v3_needs_review BOOLEAN,
  v3_review_reasons TEXT[],
  -- v3.6 outputs (to be populated when shadow runs)
  v36_processed BOOLEAN DEFAULT FALSE,
  v36_project_id UUID,
  v36_contact_id UUID,
  v36_confidence NUMERIC,
  v36_has_summary BOOLEAN,
  v36_needs_review BOOLEAN,
  v36_gate_status TEXT,
  v36_gate_reasons JSONB,
  v36_calls_raw_uuid UUID,
  -- Scoring
  project_match BOOLEAN,
  contact_match BOOLEAN,
  quality_notes TEXT,
  chad_verdict TEXT,  -- 'v3_better', 'v36_better', 'equal', 'both_wrong'
  created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE v3_v36_comparison_set IS 'Side-by-side comparison of v3 vs v3.6 outputs for readiness evaluation';;
