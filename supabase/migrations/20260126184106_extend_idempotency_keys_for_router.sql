
-- Add router-related columns to existing idempotency_keys table
ALTER TABLE public.idempotency_keys
ADD COLUMN IF NOT EXISTS router_version text,
ADD COLUMN IF NOT EXISTS result_hash text,
ADD COLUMN IF NOT EXISTS processed_at timestamptz;

-- Add index on interaction_id if not exists
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_interaction_id
ON public.idempotency_keys(interaction_id);

COMMENT ON COLUMN public.idempotency_keys.router_version IS 'Router version that processed this interaction';
COMMENT ON COLUMN public.idempotency_keys.result_hash IS 'MD5 hash of project_id|confidence for change detection';
;
