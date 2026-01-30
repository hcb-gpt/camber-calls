-- Contact Relationships Table
-- Extensible many-to-many relationship model

CREATE TABLE IF NOT EXISTS contact_relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  related_contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  relationship_type TEXT NOT NULL CHECK (relationship_type IN ('spouse', 'sibling', 'parent', 'child', 'employee', 'employer', 'business_partner', 'vendor_rep', 'other')),
  relationship_label TEXT,  -- Free text, e.g., "Office Manager", "Brother"
  strength SMALLINT DEFAULT 100 CHECK (strength >= 0 AND strength <= 100),  -- 100 = confirmed, lower = inferred
  source TEXT DEFAULT 'manual',  -- manual, inferred, system
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(contact_id, related_contact_id, relationship_type),
  CHECK (contact_id != related_contact_id)  -- No self-relationships
);

COMMENT ON TABLE contact_relationships IS 'spine_v1: Many-to-many typed relationships between contacts (spouse, sibling, employee, etc.)';
COMMENT ON COLUMN contact_relationships.strength IS '0-100 confidence: 100=confirmed manual, <100=inferred';
COMMENT ON COLUMN contact_relationships.relationship_label IS 'Optional descriptive label (e.g., Office Manager, Bookkeeper)';

CREATE INDEX IF NOT EXISTS idx_contact_relationships_contact ON contact_relationships(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_relationships_related ON contact_relationships(related_contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_relationships_type ON contact_relationships(relationship_type);;
