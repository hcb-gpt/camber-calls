-- Expand gate_status constraint to accept both uppercase and legacy lowercase values
-- This allows code flexibility while we align on a single standard

ALTER TABLE event_audit DROP CONSTRAINT event_audit_gate_status_check;

ALTER TABLE event_audit ADD CONSTRAINT event_audit_gate_status_check 
    CHECK (gate_status IN (
        'PASS', 'REJECT', 'SKIP',           -- M5 spec uppercase
        'pass', 'fail', 'needs_human',       -- Legacy lowercase  
        'reject', 'skip'                     -- Possible lowercase variants
    ));;
