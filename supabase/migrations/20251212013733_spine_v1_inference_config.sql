
-- spine_v1: Configuration table for inference thresholds
-- Allows tuning without schema changes

CREATE TABLE inference_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  config_key TEXT NOT NULL UNIQUE,
  config_value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by TEXT
);

-- Seed v1 default thresholds
INSERT INTO inference_config (config_key, config_value, description, updated_by) VALUES
  ('cost_code_auto_assign_threshold', '0.85', 'Confidence >= this value: auto-assign cost code', 'data_v1'),
  ('cost_code_review_threshold', '0.50', 'Confidence >= this but < auto: suggest + flag for review', 'data_v1'),
  ('inference_enabled_channels', '["call", "sms"]', 'Channels where financial inference runs', 'data_v1'),
  ('p0_vendor_ids', '[]', 'Contact IDs for priority vendors in QA phase', 'data_v1');

COMMENT ON TABLE inference_config IS 'spine_v1: Tunable thresholds and feature flags for Gandalf inference';
;
