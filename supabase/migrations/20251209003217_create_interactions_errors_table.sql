
-- Create error table with same structure as interactions plus error metadata
CREATE TABLE public.interactions_errors (
    -- Copy all columns from interactions
    id uuid DEFAULT gen_random_uuid(),
    interaction_id text,
    channel text,
    source_zap text,
    owner_name text,
    owner_phone text,
    contact_name text,
    contact_phone text,
    thread_key text,
    event_at_utc timestamptz,
    event_at_local timestamptz,
    ingested_at_utc timestamptz,
    human_summary text,
    ai_scheduler_json jsonb,
    future_proof_json jsonb,
    bug_flags_json jsonb,
    enrichment_conf numeric,
    has_scheduler_items boolean,
    scheduler_item_count integer,
    scheduler_schema_version integer,
    
    -- Error tracking metadata
    error_reason text,
    moved_at_utc timestamptz DEFAULT now(),
    original_id uuid
);

COMMENT ON TABLE public.interactions_errors IS 'Interactions moved here due to pipeline errors for diagnosis';
;
