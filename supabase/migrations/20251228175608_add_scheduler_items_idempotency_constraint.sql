
-- Add unique constraint for idempotency
DO $$
BEGIN
  -- First, ensure all existing rows have item_hash populated
  UPDATE public.scheduler_items 
  SET item_hash = md5(interaction_id::text || '|' || item_type || '|' || title)
  WHERE item_hash IS NULL;
  
  -- Check if constraint already exists
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'uq_scheduler_items_idempotency'
  ) THEN
    -- Add unique constraint
    ALTER TABLE public.scheduler_items 
    ADD CONSTRAINT uq_scheduler_items_idempotency 
    UNIQUE (interaction_id, item_hash);
  END IF;
END $$;

-- Create partial index for pending items (common dashboard query)
CREATE INDEX IF NOT EXISTS idx_scheduler_items_pending_by_due
ON public.scheduler_items (due_at_utc, assignee)
WHERE status = 'pending';

-- Create index for scheduler agent queries (type + status + created)
CREATE INDEX IF NOT EXISTS idx_scheduler_items_agent_query
ON public.scheduler_items (item_type, status, created_at DESC);
;
