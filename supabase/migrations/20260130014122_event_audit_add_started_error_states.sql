-- Add STARTED and ERROR to allowed gate_status values
-- Required for v3.6/v3.7 write-ahead durability pattern

ALTER TABLE event_audit 
DROP CONSTRAINT event_audit_gate_status_check;

ALTER TABLE event_audit 
ADD CONSTRAINT event_audit_gate_status_check 
CHECK (gate_status = ANY (ARRAY['PASS', 'REJECT', 'SKIP', 'NEEDS_REVIEW', 'STARTED', 'ERROR']));;
