CREATE TABLE IF NOT EXISTS project_contacts_promotion_log (
  id SERIAL PRIMARY KEY,
  inserted_at TIMESTAMPTZ DEFAULT now(),
  inserted_by TEXT DEFAULT 'data_batch',
  batch_id TEXT,
  contact_id UUID REFERENCES contacts(id),
  project_id UUID REFERENCES projects(id),
  is_active BOOLEAN,
  method TEXT,
  notes TEXT
);;
