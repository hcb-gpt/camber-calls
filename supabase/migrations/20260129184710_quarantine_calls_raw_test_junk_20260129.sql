-- Quarantine remaining test_* junk in calls_raw (v3-github era)
CREATE TABLE quarantine_calls_raw_test_20260129T1755Z AS
SELECT * FROM calls_raw 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';

-- Delete after quarantine
DELETE FROM calls_raw 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';;
