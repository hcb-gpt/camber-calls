-- Quarantine and delete test_* rows from pipedream_run_logs

CREATE TABLE quarantine_pipedream_run_logs_20260129T1800Z AS
SELECT * FROM pipedream_run_logs 
WHERE interaction_id LIKE 'test_%';

DELETE FROM pipedream_run_logs 
WHERE interaction_id LIKE 'test_%';;
