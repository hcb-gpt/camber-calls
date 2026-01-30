
-- Prevent duplicate belief claims
CREATE UNIQUE INDEX IF NOT EXISTS belief_claims_dedup_idx
ON belief_claims (project_id, claim_type, md5(short_text));

COMMENT ON INDEX belief_claims_dedup_idx IS 
'Prevents duplicate claims with same project, type, and text. Uses md5 hash of short_text for efficiency.';
;
