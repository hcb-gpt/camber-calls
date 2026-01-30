
-- Drop duplicate index on pipedream_run_logs
DROP INDEX IF EXISTS idx_pipedream_run_logs_stage_created;

-- Drop unused scheduler_items indexes (never queried)
DROP INDEX IF EXISTS idx_scheduler_items_type;
DROP INDEX IF EXISTS idx_scheduler_items_due;
DROP INDEX IF EXISTS idx_scheduler_items_status_due;
DROP INDEX IF EXISTS idx_scheduler_items_pending_by_due;
DROP INDEX IF EXISTS idx_scheduler_items_agent_query;
DROP INDEX IF EXISTS idx_scheduler_items_start;
;
