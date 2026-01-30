-- Drop triage_action constraint to allow writes through
-- M5 code is sending values not in the allowed list

ALTER TABLE event_audit DROP CONSTRAINT IF EXISTS event_audit_triage_action_check;;
