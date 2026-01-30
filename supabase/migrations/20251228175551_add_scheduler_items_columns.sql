
-- Add payload column (raw item from ai_scheduler_json)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'scheduler_items' 
    AND column_name = 'payload'
  ) THEN
    ALTER TABLE public.scheduler_items 
    ADD COLUMN payload jsonb;
    
    COMMENT ON COLUMN public.scheduler_items.payload IS 
      'Raw scheduler item as extracted from interactions.ai_scheduler_json';
  END IF;
END $$;

-- Add meta column (parser hints)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'scheduler_items' 
    AND column_name = 'meta'
  ) THEN
    ALTER TABLE public.scheduler_items 
    ADD COLUMN meta jsonb DEFAULT '{}'::jsonb;
    
    COMMENT ON COLUMN public.scheduler_items.meta IS 
      'Parser metadata: source_field_mapping, extraction_method, confidence';
  END IF;
END $$;

-- Add source column (origin of the item)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'scheduler_items' 
    AND column_name = 'source'
  ) THEN
    ALTER TABLE public.scheduler_items 
    ADD COLUMN source text DEFAULT 'ai'::text;
  END IF;
END $$;

-- Add item_hash column (for idempotency)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'scheduler_items' 
    AND column_name = 'item_hash'
  ) THEN
    ALTER TABLE public.scheduler_items 
    ADD COLUMN item_hash text;
    
    COMMENT ON COLUMN public.scheduler_items.item_hash IS 
      'MD5 hash of (interaction_id + item_type + title) for duplicate detection';
  END IF;
END $$;

-- Add index on item_hash for fast lookups
CREATE INDEX IF NOT EXISTS idx_scheduler_items_hash 
ON public.scheduler_items (item_hash);

-- Add composite index for common query pattern (status + due date)
CREATE INDEX IF NOT EXISTS idx_scheduler_items_status_due 
ON public.scheduler_items (status, due_at_utc) 
WHERE status = 'pending';

-- Add index on source for filtering
CREATE INDEX IF NOT EXISTS idx_scheduler_items_source 
ON public.scheduler_items (source);
;
