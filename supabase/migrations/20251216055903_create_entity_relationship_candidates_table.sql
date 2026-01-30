-- Entity Relationship Candidates Table
-- Holds mined/inferred relationships pending approval

CREATE TABLE IF NOT EXISTS entity_relationship_candidates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Source entity (resolved contact or raw identifier)
  source_contact_id UUID REFERENCES contacts(id),
  source_identifier TEXT,  -- Phone/email/name if not resolved
  
  -- Target entity (resolved contact or inferred name)
  target_contact_id UUID REFERENCES contacts(id),
  target_identifier TEXT,  -- Inferred name if not resolved (e.g., "Austin's wife")
  
  -- Relationship details
  relationship_type TEXT NOT NULL CHECK (relationship_type IN (
    'spouse', 'sibling', 'parent', 'child', 
    'employee', 'employer', 'business_partner', 'vendor_rep', 'other'
  )),
  relationship_label TEXT,  -- Free text (e.g., "Office Manager", "Brother")
  
  -- Confidence and provenance
  confidence SMALLINT DEFAULT 70 CHECK (confidence >= 0 AND confidence <= 100),
  evidence_snippet TEXT,
  source_thread TEXT,
  extraction_method TEXT DEFAULT 'regex',  -- regex, nlp, manual
  
  -- Status workflow
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'merged')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  merged_relationship_id UUID REFERENCES contact_relationships(id),
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE entity_relationship_candidates IS 'spine_v1: Candidate relationships extracted from corpus, pending human approval';

CREATE INDEX IF NOT EXISTS idx_erc_source_contact ON entity_relationship_candidates(source_contact_id);
CREATE INDEX IF NOT EXISTS idx_erc_target_contact ON entity_relationship_candidates(target_contact_id);
CREATE INDEX IF NOT EXISTS idx_erc_status ON entity_relationship_candidates(status);
CREATE INDEX IF NOT EXISTS idx_erc_confidence ON entity_relationship_candidates(confidence DESC);;
