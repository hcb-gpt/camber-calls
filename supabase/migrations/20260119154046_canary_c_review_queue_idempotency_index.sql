
-- Step 4: Create unique index for idempotency
CREATE UNIQUE INDEX journal_review_queue_call_item_uniq 
ON journal_review_queue (call_id, item_type, item_id);

-- Add index on call_id for lookups
CREATE INDEX idx_journal_review_queue_call_id ON journal_review_queue(call_id);
;
