-- Delete residual junk after quarantine

-- Delete from interactions
DELETE FROM interactions 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';

-- Delete from pipeline_logs  
DELETE FROM pipeline_logs 
WHERE interaction_id LIKE 'unknown_%' OR interaction_id LIKE 'test_%';;
