-- Create pipedream_run_logs table for Pipedream workflow debugging
CREATE TABLE IF NOT EXISTS public.pipedream_run_logs (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at      timestamptz NOT NULL DEFAULT now(),
    interaction_id  text,
    stage           text NOT NULL,
    ok              boolean NOT NULL DEFAULT true,
    skipped         boolean NOT NULL DEFAULT false,
    error_code      text,
    message         text,
    headers         jsonb,
    raw_body        text,
    parsed_body     jsonb,
    meta            jsonb
);

-- Index for querying by interaction_id + time
CREATE INDEX IF NOT EXISTS idx_pipedream_run_logs_interaction_created
    ON public.pipedream_run_logs (interaction_id, created_at DESC)
    WHERE interaction_id IS NOT NULL;

-- Index for querying by stage + time
CREATE INDEX IF NOT EXISTS idx_pipedream_run_logs_stage_created
    ON public.pipedream_run_logs (stage, created_at DESC);

-- Table comment
COMMENT ON TABLE public.pipedream_run_logs IS 
    'Structured logs for Pipedream workflow runs. Service-role access only.';

-- Enable RLS (no policies = service role bypass only)
ALTER TABLE public.pipedream_run_logs ENABLE ROW LEVEL SECURITY;;
