-- Migration: Add first-class project attribution and identity columns to interactions
-- This makes interactions the SSOT for router output per STRAT directive

ALTER TABLE interactions
  ADD COLUMN IF NOT EXISTS contact_id uuid REFERENCES contacts(id),
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS project_attribution_confidence numeric(3,2),
  ADD COLUMN IF NOT EXISTS needs_review boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS review_reasons text[],
  ADD COLUMN IF NOT EXISTS context_receipt jsonb;

-- Add index for common query patterns
CREATE INDEX IF NOT EXISTS idx_interactions_project_id ON interactions(project_id);
CREATE INDEX IF NOT EXISTS idx_interactions_contact_id ON interactions(contact_id);
CREATE INDEX IF NOT EXISTS idx_interactions_needs_review ON interactions(needs_review) WHERE needs_review = true;

COMMENT ON COLUMN interactions.contact_id IS 'FK to contacts - SSOT for identity (phone kept for display/audit)';
COMMENT ON COLUMN interactions.project_id IS 'Router-attributed project - nullable until attributed';
COMMENT ON COLUMN interactions.project_attribution_confidence IS 'Router confidence 0.00-1.00';
COMMENT ON COLUMN interactions.needs_review IS 'True if confidence below threshold or cross-project ambiguity';
COMMENT ON COLUMN interactions.review_reasons IS 'Array of reason codes for review queue';
COMMENT ON COLUMN interactions.context_receipt IS 'Receipt anchor: what context was assembled, what was truncated';;
