-- Add columns required by attribution idempotency spec
-- Preserving existing schema for backward compatibility

-- Add call_sid alias (existing 'key' column serves this purpose but spec wants explicit)
ALTER TABLE public.idempotency_keys 
ADD COLUMN IF NOT EXISTS call_sid text;

-- Add router_version
ALTER TABLE public.idempotency_keys 
ADD COLUMN IF NOT EXISTS router_version text;

-- Add processed_at
ALTER TABLE public.idempotency_keys 
ADD COLUMN IF NOT EXISTS processed_at timestamptz;

-- Add result_hash for attribution tracking
ALTER TABLE public.idempotency_keys 
ADD COLUMN IF NOT EXISTS result_hash text;

-- Add created_at if missing
ALTER TABLE public.idempotency_keys 
ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT NOW();

-- Backfill call_sid from key where applicable
UPDATE idempotency_keys 
SET call_sid = key 
WHERE call_sid IS NULL AND key LIKE 'cll_%';

-- Backfill processed_at from first_seen_at
UPDATE idempotency_keys 
SET processed_at = first_seen_at 
WHERE processed_at IS NULL;

-- Backfill created_at from first_seen_at
UPDATE idempotency_keys 
SET created_at = first_seen_at 
WHERE created_at IS NULL;

-- Create index on interaction_id (can't add UNIQUE since many are NULL)
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_interaction_id
ON idempotency_keys(interaction_id)
WHERE interaction_id IS NOT NULL;;
