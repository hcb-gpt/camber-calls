
-- Migration: Add claim-level attribution columns to journal_claims
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS project_candidates JSONB,
ADD COLUMN IF NOT EXISTS attribution_confidence FLOAT;

-- project_id already exists (nullable) — no change needed
-- project_candidates: top-k with scores + evidence pointers
-- attribution_confidence: 0.0-1.0 score for the chosen project_id

COMMENT ON COLUMN journal_claims.project_candidates IS 'Top-k project candidates with scores and evidence pointers. Format: [{project_id, score, evidence_pointer_id}, ...]';
COMMENT ON COLUMN journal_claims.attribution_confidence IS 'Confidence score (0-1) for the assigned project_id. NULL if unassigned.';
;
