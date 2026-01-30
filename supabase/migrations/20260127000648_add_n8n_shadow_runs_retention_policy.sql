-- T5: Retention policy - delete shadow runs older than 14 days
-- This creates a function and scheduled job for cleanup

-- Create cleanup function
CREATE OR REPLACE FUNCTION cleanup_old_shadow_runs()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  -- Delete shadow runs older than 14 days
  DELETE FROM n8n_shadow_runs
  WHERE created_at < NOW() - INTERVAL '14 days'
    AND exported_at IS NOT NULL;  -- Only delete if already exported
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  -- Also delete old error records
  DELETE FROM n8n_shadow_errors
  WHERE created_at < NOW() - INTERVAL '14 days'
    AND resolved_at IS NOT NULL;  -- Only delete if resolved
  
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Add comment documenting retention policy
COMMENT ON FUNCTION cleanup_old_shadow_runs() IS 
  'T5 Retention: Deletes exported shadow runs older than 14 days. Call via pg_cron or manual trigger.';;
