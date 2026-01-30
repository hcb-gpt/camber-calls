
-- ================================================
-- EVENT_AUDIT: AI-forward gate + triage log
-- Every inbound event is logged here before persistence decision
-- ================================================

CREATE TABLE event_audit (
  id bigserial PRIMARY KEY,
  interaction_id text NOT NULL,
  received_at_utc timestamptz DEFAULT now(),
  
  -- === GATE RESULTS ===
  gate_status text NOT NULL CHECK (gate_status IN ('pass', 'fail', 'needs_human')),
  gate_reasons jsonb DEFAULT '[]'::jsonb,
  
  -- === INVARIANT CHECKS ===
  i1_phone_present boolean,
  i2_unique_id boolean,
  i5_lineage_present boolean,
  
  -- === TRIAGE RESULTS ===
  triage_action text CHECK (triage_action IN ('auto_persist', 'auto_fix', 'queue_human', 'reject')),
  triage_confidence numeric(4,3),
  suggested_fix jsonb,
  
  -- === LINEAGE ===
  source_system text,
  source_run_id text,
  source_zap_id text,
  raw_payload_hash text,
  
  -- === OUTCOME ===
  persisted_to_calls_raw boolean DEFAULT false,
  persisted_at_utc timestamptz,
  calls_raw_id bigint,
  
  -- === AUDIT ===
  pipeline_version text,
  processed_by text,
  
  CONSTRAINT unique_event_per_receive UNIQUE(interaction_id, received_at_utc)
);

-- Indexes for common queries
CREATE INDEX idx_event_audit_gate_status ON event_audit(gate_status);
CREATE INDEX idx_event_audit_needs_human ON event_audit(gate_status) WHERE gate_status = 'needs_human';
CREATE INDEX idx_event_audit_not_persisted ON event_audit(persisted_to_calls_raw) WHERE NOT persisted_to_calls_raw;
CREATE INDEX idx_event_audit_interaction ON event_audit(interaction_id);
CREATE INDEX idx_event_audit_received ON event_audit(received_at_utc DESC);

COMMENT ON TABLE event_audit IS 'AI-forward gate: logs every inbound event with invariant checks, triage decision, and persistence outcome';
;
