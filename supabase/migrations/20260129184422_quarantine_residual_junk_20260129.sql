-- Quarantine residual junk from interactions and pipeline_logs

-- Quarantine interactions junk
CREATE TABLE quarantine_interactions_20260129T1745Z AS
SELECT * FROM interactions 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';

-- Quarantine pipeline_logs junk
CREATE TABLE quarantine_pipeline_logs_20260129T1745Z AS
SELECT * FROM pipeline_logs 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';;
