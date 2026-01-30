-- Add address fields, parcel fields, job type, and entity fields to projects table
ALTER TABLE projects 
  ADD COLUMN IF NOT EXISTS street text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text DEFAULT 'GA',
  ADD COLUMN IF NOT EXISTS zip text,
  ADD COLUMN IF NOT EXISTS map_id text,
  ADD COLUMN IF NOT EXISTS parcel_id text,
  ADD COLUMN IF NOT EXISTS parcel_info text,
  ADD COLUMN IF NOT EXISTS job_type text CHECK (job_type IN ('New Build', 'Remodel', 'Addition')),
  ADD COLUMN IF NOT EXISTS client_entity text,
  ADD COLUMN IF NOT EXISTS client_entity_alias text;

COMMENT ON COLUMN projects.parcel_info IS 'Full parcel string for display (e.g., Map 04R Parcel 008B)';
COMMENT ON COLUMN projects.client_entity IS 'LLC/company name if applicable';
COMMENT ON COLUMN projects.client_entity_alias IS 'DBA/trade name (e.g., Waggin Tails Farm)';;
