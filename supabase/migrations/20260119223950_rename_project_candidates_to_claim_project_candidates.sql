
-- Rename column to match DEV's v1.4 code expectations
ALTER TABLE journal_claims 
RENAME COLUMN project_candidates TO claim_project_candidates;

-- Also add claim_project_id if missing (DEV's code writes to this)
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS claim_project_id UUID;

COMMENT ON COLUMN journal_claims.claim_project_candidates IS 'Top-k project candidates with scores and evidence. Format: [{project_id, score, evidence}, ...]';
COMMENT ON COLUMN journal_claims.claim_project_id IS 'Confident project attribution for this claim. NULL if ambiguous (routed to review).';
;
