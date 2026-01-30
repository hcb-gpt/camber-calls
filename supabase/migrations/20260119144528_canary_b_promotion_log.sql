
-- Canary-B: Create promotion_log for rollback tracking
CREATE TABLE promotion_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL,
  claim_id UUID NOT NULL,  -- the belief_claims.id created
  journal_claim_id UUID NOT NULL,  -- the original journal_claims.id
  promoted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_promotion_log_run ON promotion_log(run_id);
CREATE INDEX idx_promotion_log_claim ON promotion_log(claim_id);

COMMENT ON TABLE promotion_log IS 'Tracks which journal_claims were promoted to belief_claims, enabling rollback by run_id';
;
