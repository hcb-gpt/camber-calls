-- Fix event_audit gate_status constraint to match M5 contract
-- Old values: 'pass', 'fail', 'needs_human' (lowercase, legacy)
-- New values: 'PASS', 'REJECT', 'SKIP' (uppercase, M5 spec)

ALTER TABLE event_audit DROP CONSTRAINT event_audit_gate_status_check;

ALTER TABLE event_audit ADD CONSTRAINT event_audit_gate_status_check 
    CHECK (gate_status IN ('PASS', 'REJECT', 'SKIP'));;
