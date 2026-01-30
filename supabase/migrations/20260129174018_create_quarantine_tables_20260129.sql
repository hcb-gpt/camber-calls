-- Step 1: Create quarantine tables with UTC timestamp

-- Quarantine table for calls_raw v3.6 rows
CREATE TABLE quarantine_calls_raw_20260129T1740Z AS
SELECT * FROM calls_raw WHERE pipeline_version = 'v3.6';

-- Quarantine table for event_audit bad rows (excluding SHADOW)
CREATE TABLE quarantine_event_audit_20260129T1740Z AS
SELECT * FROM event_audit 
WHERE pipeline_version = 'v3.6' 
  AND (persisted_to_calls_raw = true 
       OR interaction_id LIKE 'unknown_%' 
       OR interaction_id LIKE 'test_%')
  AND interaction_id NOT LIKE 'cll_SHADOW_V36_%';;
