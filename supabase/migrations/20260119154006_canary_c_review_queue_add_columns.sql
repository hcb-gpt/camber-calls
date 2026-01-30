
-- Step 1: Add columns
ALTER TABLE journal_review_queue ADD COLUMN call_id TEXT;
ALTER TABLE journal_review_queue ADD COLUMN project_id UUID;

COMMENT ON COLUMN journal_review_queue.call_id IS 'Call interaction_id for idempotent upserts and traceability';
COMMENT ON COLUMN journal_review_queue.project_id IS 'Project UUID for filtering and traceability';
;
