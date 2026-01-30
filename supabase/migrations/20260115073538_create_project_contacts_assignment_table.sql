-- Migration: Create project_contacts as SSOT for vendor/subcontractor↔project assignment
-- This is the missing foundation STRAT identified - enables deterministic candidate project sets

CREATE TABLE IF NOT EXISTS project_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES contacts(id),
  project_id uuid NOT NULL REFERENCES projects(id),
  role text,                    -- e.g., 'lead', 'backup', 'specialist'
  trade text,                   -- e.g., 'Masonry', 'Framing' (denormalized for query convenience)
  is_active boolean DEFAULT true,
  assigned_at timestamptz DEFAULT now(),
  source text,                  -- provenance: 'manual', 'buildertrend_sync', 'inferred'
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  UNIQUE(contact_id, project_id)
);

-- Indexes for Context Assembly candidate selection
CREATE INDEX IF NOT EXISTS idx_project_contacts_contact_id ON project_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_project_contacts_project_id ON project_contacts(project_id);
CREATE INDEX IF NOT EXISTS idx_project_contacts_active ON project_contacts(contact_id, project_id) WHERE is_active = true;

COMMENT ON TABLE project_contacts IS 'SSOT for vendor/sub↔project assignment. Used by Context Assembly for candidate project selection.';
COMMENT ON COLUMN project_contacts.source IS 'Provenance tracking: manual, buildertrend_sync, inferred from interactions';;
