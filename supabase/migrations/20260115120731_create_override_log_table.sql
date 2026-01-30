-- Migration: Create override_log as canonical audit trail for corrections
-- Captures who/what/when + the actual correction

CREATE TABLE IF NOT EXISTS override_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- What was corrected
  entity_type text NOT NULL,  -- 'interaction', 'scheduler_item'
  entity_id uuid NOT NULL,
  field_name text NOT NULL,  -- 'project_id', 'attribution_status', 'contact_id', etc.
  
  -- The correction
  from_value text,  -- null if was unset
  to_value text,    -- null if setting to unknown
  
  -- Provenance
  user_id text,
  reason text,
  review_queue_id uuid REFERENCES review_queue(id),  -- optional link to the review item
  
  -- Timestamp
  created_at timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT chk_override_log_entity_type CHECK (entity_type IN ('interaction', 'scheduler_item'))
);

-- Indexes for audit queries
CREATE INDEX IF NOT EXISTS idx_override_log_entity ON override_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_override_log_created ON override_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_override_log_field ON override_log(field_name);

COMMENT ON TABLE override_log IS 'Audit trail for all human corrections. Every confirm/reject/edit is logged here.';
COMMENT ON COLUMN override_log.from_value IS 'Original value as text (null if previously unset)';
COMMENT ON COLUMN override_log.to_value IS 'New value as text (null if correcting to unknown)';;
