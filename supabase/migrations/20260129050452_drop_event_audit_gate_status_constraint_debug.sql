-- Temporarily drop constraint to see what value M5 is actually sending
-- We will re-add after identifying the actual values

ALTER TABLE event_audit DROP CONSTRAINT IF EXISTS event_audit_gate_status_check;;
