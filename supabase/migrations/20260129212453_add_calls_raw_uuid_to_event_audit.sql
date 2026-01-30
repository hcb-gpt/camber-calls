-- Migration: Add calls_raw_uuid column to event_audit
-- Reason: calls_raw.id is UUID, event_audit.calls_raw_id is BIGINT (type mismatch)
-- Option B: Add new UUID column, keep bigint deprecated

ALTER TABLE event_audit 
ADD COLUMN IF NOT EXISTS calls_raw_uuid UUID NULL;

COMMENT ON COLUMN event_audit.calls_raw_uuid IS 'FK to calls_raw.id (UUID). Replaces calls_raw_id (bigint) which had type mismatch.';
COMMENT ON COLUMN event_audit.calls_raw_id IS 'DEPRECATED: Type mismatch with calls_raw.id (UUID). Use calls_raw_uuid instead.';;
