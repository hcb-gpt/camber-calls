
-- Migration: add_scheduler_indexes_v2
-- Purpose: Add index for start_at_utc and optimize for "items created last 24h" queries

-- Index for start_at_utc (events/appointments)
CREATE INDEX IF NOT EXISTS idx_scheduler_items_start 
ON scheduler_items (start_at_utc) 
WHERE start_at_utc IS NOT NULL;

-- Composite index for QC query: items by type, status, in last 24h
CREATE INDEX IF NOT EXISTS idx_scheduler_items_created_type_status 
ON scheduler_items (created_at, item_type, status);

-- Comment update for documentation
COMMENT ON TABLE scheduler_items IS 'brain_v1: Schedulable tasks/events derived from interactions. See DATA memo 28 for schema rationale.';
;
