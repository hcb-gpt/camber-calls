-- Restore gate_status and triage_action constraints with correct M5 values

-- gate_status: PASS (valid), REJECT (invalid data), SKIP (audit only), NEEDS_REVIEW
ALTER TABLE event_audit ADD CONSTRAINT event_audit_gate_status_check 
    CHECK (gate_status IN ('PASS', 'REJECT', 'SKIP', 'NEEDS_REVIEW'));

-- triage_action: matches gate_status semantics for now
ALTER TABLE event_audit ADD CONSTRAINT event_audit_triage_action_check 
    CHECK (triage_action IN ('PASS', 'REJECT', 'SKIP', 'NEEDS_REVIEW'));;
