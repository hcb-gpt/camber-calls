-- Add pipeline_version column to calls_raw for easy filtering
ALTER TABLE calls_raw 
ADD COLUMN IF NOT EXISTS pipeline_version TEXT DEFAULT NULL;

-- Add test_batch column for batch identification
ALTER TABLE calls_raw 
ADD COLUMN IF NOT EXISTS test_batch TEXT DEFAULT NULL;

-- Add index for filtering by pipeline version
CREATE INDEX IF NOT EXISTS idx_calls_raw_pipeline_version 
ON calls_raw(pipeline_version) 
WHERE pipeline_version IS NOT NULL;

-- Comment for documentation
COMMENT ON COLUMN calls_raw.pipeline_version IS 'Pipeline version that processed this call (e.g., v3, v3.5)';
COMMENT ON COLUMN calls_raw.test_batch IS 'Test batch identifier for grouping test runs';;
