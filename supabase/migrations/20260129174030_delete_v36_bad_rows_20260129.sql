-- Step 2: Delete after quarantine (data is safely copied)

-- Delete ALL calls_raw where pipeline_version='v3.6'
DELETE FROM calls_raw WHERE pipeline_version = 'v3.6';

-- Delete known-bad event_audit rows (preserving SHADOW validation rows)
DELETE FROM event_audit 
WHERE pipeline_version = 'v3.6' 
  AND (persisted_to_calls_raw = true 
       OR interaction_id LIKE 'unknown_%' 
       OR interaction_id LIKE 'test_%')
  AND interaction_id NOT LIKE 'cll_SHADOW_V36_%';;
