CREATE TABLE IF NOT EXISTS project_clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  client_role text NOT NULL DEFAULT 'primary' CHECK (client_role IN ('primary', 'secondary', 'tertiary')),
  is_primary_contact boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(project_id, contact_id)
);

COMMENT ON TABLE project_clients IS 'Junction table linking projects to client contacts';
COMMENT ON COLUMN project_clients.client_role IS 'primary=main client, secondary=spouse/partner, tertiary=additional stakeholder';
COMMENT ON COLUMN project_clients.is_primary_contact IS 'True if this is the go-to contact for project communications';

CREATE INDEX IF NOT EXISTS idx_project_clients_project ON project_clients(project_id);
CREATE INDEX IF NOT EXISTS idx_project_clients_contact ON project_clients(contact_id);;
