
-- Migration: Add source_run_id for rollback-by-run support
-- This enables rolling back all claims promoted from a specific journal_run

ALTER TABLE belief_claims
ADD COLUMN IF NOT EXISTS source_run_id UUID REFERENCES journal_runs(run_id);

CREATE INDEX IF NOT EXISTS idx_belief_claims_source_run_id
ON belief_claims(source_run_id);

COMMENT ON COLUMN belief_claims.source_run_id IS 'The journal_run that promoted this claim. Used for rollback-by-run.';
;
