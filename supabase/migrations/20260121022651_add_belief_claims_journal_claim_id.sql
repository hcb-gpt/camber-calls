-- Add journal_claim_id to belief_claims for promotion idempotency
-- This ensures a journal_claim can only be promoted to belief_claims once

ALTER TABLE belief_claims 
ADD COLUMN journal_claim_id UUID REFERENCES journal_claims(id);

-- Create unique constraint to enforce idempotency
ALTER TABLE belief_claims
ADD CONSTRAINT belief_claims_journal_claim_id_key UNIQUE (journal_claim_id);

-- Create index for lookups
CREATE INDEX idx_belief_claims_journal_claim_id ON belief_claims(journal_claim_id);

COMMENT ON COLUMN belief_claims.journal_claim_id IS 'Source journal_claim that was promoted. Unique constraint prevents duplicate promotions.';;
