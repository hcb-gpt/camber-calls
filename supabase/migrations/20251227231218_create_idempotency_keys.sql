-- 1) Create idempotency_keys table
CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    key             text NOT NULL,
    interaction_id  text,
    source          text DEFAULT 'pipedream',
    payload_hash    text,
    first_payload   jsonb,
    hit_count       integer NOT NULL DEFAULT 1,
    first_seen_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz NOT NULL DEFAULT now(),
    
    CONSTRAINT idempotency_keys_key_unique UNIQUE (key)
);

-- 2) Index for interaction_id lookups (nullable, so partial index)
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_interaction_id 
    ON public.idempotency_keys (interaction_id) 
    WHERE interaction_id IS NOT NULL;

-- 3) Index for cleanup queries by age
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_last_seen 
    ON public.idempotency_keys (last_seen_at);

-- 4) Table comment
COMMENT ON TABLE public.idempotency_keys IS 
    'Webhook idempotency tracking for Pipedream retry protection. Key format: itx:<interaction_id> or custom.';

-- 5) Enable RLS but add no policies (service role bypasses)
ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

-- 6) Atomic upsert RPC: insert new or increment hit_count + update last_seen_at
CREATE OR REPLACE FUNCTION public.upsert_idempotency_key(
    p_key           text,
    p_interaction_id text DEFAULT NULL,
    p_source        text DEFAULT 'pipedream',
    p_payload_hash  text DEFAULT NULL,
    p_first_payload jsonb DEFAULT NULL
)
RETURNS TABLE (
    is_duplicate    boolean,
    hit_count       integer,
    first_seen_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_id uuid;
    v_hit_count integer;
    v_first_seen timestamptz;
BEGIN
    -- Attempt insert; on conflict, update hit_count and last_seen_at
    INSERT INTO public.idempotency_keys (key, interaction_id, source, payload_hash, first_payload)
    VALUES (p_key, p_interaction_id, p_source, p_payload_hash, p_first_payload)
    ON CONFLICT (key) DO UPDATE SET
        hit_count = idempotency_keys.hit_count + 1,
        last_seen_at = now()
    RETURNING 
        idempotency_keys.id,
        idempotency_keys.hit_count,
        idempotency_keys.first_seen_at
    INTO v_existing_id, v_hit_count, v_first_seen;
    
    -- If hit_count > 1, this was a duplicate
    RETURN QUERY SELECT 
        (v_hit_count > 1) AS is_duplicate,
        v_hit_count,
        v_first_seen;
END;
$$;

COMMENT ON FUNCTION public.upsert_idempotency_key IS 
    'Atomic idempotency check: returns is_duplicate=true if key existed, increments hit_count. Race-safe via ON CONFLICT.';;
