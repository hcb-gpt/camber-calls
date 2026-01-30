-- Migration: Create n8n_shadow_runs table for Phase 0 shadow mode
CREATE TABLE IF NOT EXISTS n8n_shadow_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Core identifiers
  interaction_id UUID NOT NULL,
  run_id UUID NOT NULL,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  pipeline_started_at TIMESTAMPTZ,
  pipeline_completed_at TIMESTAMPTZ,
  
  -- Hashes (SHA-256 full hex per STRAT-24 directive)
  manifest_hash TEXT NOT NULL,
  prompt_hash TEXT,
  
  -- JSONB columns for structured data
  classification JSONB,
  router_output JSONB,
  gatekeeper_output JSONB,
  receipts JSONB NOT NULL,
  
  -- Comparison fields (filled by RND-7 harness)
  pd_run_id UUID,
  pd_project_id UUID,
  pd_confidence NUMERIC,
  match_status TEXT,
  diff_details JSONB,
  
  -- Export tracking
  exported_at TIMESTAMPTZ,
  export_batch_id TEXT
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_shadow_interaction ON n8n_shadow_runs(interaction_id);
CREATE INDEX IF NOT EXISTS idx_shadow_run ON n8n_shadow_runs(run_id);
CREATE INDEX IF NOT EXISTS idx_shadow_created ON n8n_shadow_runs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shadow_match ON n8n_shadow_runs(match_status) WHERE match_status IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shadow_export ON n8n_shadow_runs(export_batch_id) WHERE export_batch_id IS NOT NULL;

COMMENT ON TABLE n8n_shadow_runs IS 'Shadow mode outputs from n8n pipeline v4. No production writes - evaluation only.';;
