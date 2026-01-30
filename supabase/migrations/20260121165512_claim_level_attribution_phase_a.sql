-- ============================================================================
-- MIGRATION: Claim-Level Attribution (Phase A)
-- SPEC: tram_2026-01-21_1400_fr_strata_to_dev_SPEC_claim_level_attribution.md
-- Author: DATA
-- Date: 2026-01-21
-- ============================================================================

-- ============================================================================
-- PART 1: SCHEMA CHANGES - journal_claims (MISSING COLUMNS ONLY)
-- ============================================================================

-- Project attribution confidence (separate from attribution_confidence which is float8)
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS claim_project_confidence NUMERIC(3,2);

-- Speaker attribution (per-claim)
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS speaker_label TEXT,
ADD COLUMN IF NOT EXISTS speaker_contact_id UUID REFERENCES contacts(id),
ADD COLUMN IF NOT EXISTS speaker_is_internal BOOLEAN,
ADD COLUMN IF NOT EXISTS testimony_type TEXT;

-- Reported speech tracking
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS reported_by_label TEXT,
ADD COLUMN IF NOT EXISTS reported_by_contact_id UUID REFERENCES contacts(id);

-- ============================================================================
-- PART 2: SCHEMA CHANGES - interactions
-- ============================================================================

ALTER TABLE interactions
ADD COLUMN IF NOT EXISTS candidate_projects JSONB DEFAULT '[]';

-- ============================================================================
-- PART 3: INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_journal_claims_claim_project_id 
ON journal_claims(claim_project_id);

CREATE INDEX IF NOT EXISTS idx_journal_claims_speaker_contact_id 
ON journal_claims(speaker_contact_id);

CREATE INDEX IF NOT EXISTS idx_journal_claims_testimony_type 
ON journal_claims(testimony_type);

CREATE INDEX IF NOT EXISTS idx_interactions_candidate_projects 
ON interactions USING GIN(candidate_projects);;
