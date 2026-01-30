
-- Create interactions table per 02_supabase_schema_and_time_rules_v1.txt
CREATE TABLE public.interactions (
    -- Primary key
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Identity
    interaction_id text UNIQUE NOT NULL,
    channel text NOT NULL,  -- 'call' | 'sms' | 'email' | etc.
    source_zap text,
    
    -- Owner/Contact
    owner_name text,
    owner_phone text,
    contact_name text,
    contact_phone text,
    thread_key text,
    
    -- Time columns
    event_at_utc timestamptz,
    event_at_local timestamptz,
    ingested_at_utc timestamptz DEFAULT now(),
    
    -- AI / semantics
    human_summary text,
    ai_scheduler_json jsonb,
    future_proof_json jsonb,
    bug_flags_json jsonb,
    enrichment_conf numeric,
    
    -- Scheduler helpers (populated by normalizer)
    has_scheduler_items boolean DEFAULT false,
    scheduler_item_count integer DEFAULT 0,
    scheduler_schema_version integer DEFAULT 0
);

-- Indexes for common query patterns
CREATE INDEX interactions_channel_idx ON public.interactions (channel);
CREATE INDEX interactions_owner_phone_idx ON public.interactions (owner_phone);
CREATE INDEX interactions_contact_phone_idx ON public.interactions (contact_phone);
CREATE INDEX interactions_event_at_utc_idx ON public.interactions (event_at_utc DESC);
CREATE INDEX interactions_owner_event_idx ON public.interactions (owner_phone, event_at_utc DESC);

-- Comment
COMMENT ON TABLE public.interactions IS 'One row per interaction (call, SMS, email) for supa scheduler v1';
;
