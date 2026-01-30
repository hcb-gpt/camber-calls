-- Migration: Create n8n_shadow_errors table for failed shadow persists
CREATE TABLE IF NOT EXISTS n8n_shadow_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Original identifiers
  interaction_id UUID,
  run_id UUID,
  
  -- Error details
  error_type TEXT NOT NULL,
  error_message TEXT,
  error_stack TEXT,
  
  -- Preserved data for retry
  original_payload JSONB NOT NULL,
  
  -- Retry tracking
  retry_count INTEGER DEFAULT 0,
  last_retry_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  resolved_by TEXT
);

-- Index for finding unresolved errors
CREATE INDEX IF NOT EXISTS idx_shadow_errors_unresolved 
  ON n8n_shadow_errors(created_at DESC) 
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_shadow_errors_interaction 
  ON n8n_shadow_errors(interaction_id);

COMMENT ON TABLE n8n_shadow_errors IS 'Dead-letter queue for failed shadow run persists. Allows retry and debugging.';;
