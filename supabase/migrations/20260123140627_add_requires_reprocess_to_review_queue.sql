-- Add requires_reprocess flag to review_queue
-- This tracks items that need pipeline rerun to benefit from newer version fixes
ALTER TABLE review_queue 
ADD COLUMN IF NOT EXISTS requires_reprocess BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN review_queue.requires_reprocess IS 'True if item needs pipeline rerun to benefit from version fixes';;
