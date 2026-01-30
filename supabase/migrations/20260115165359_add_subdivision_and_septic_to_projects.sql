-- Add subdivision and septic columns to projects table
ALTER TABLE projects 
ADD COLUMN IF NOT EXISTS subdivision_name text,
ADD COLUMN IF NOT EXISTS lot_number text,
ADD COLUMN IF NOT EXISTS septic_info jsonb;

COMMENT ON COLUMN projects.subdivision_name IS 'Name of subdivision if applicable';
COMMENT ON COLUMN projects.lot_number IS 'Lot number within subdivision';
COMMENT ON COLUMN projects.septic_info IS 'Existing septic system details: {tank_size_gal, bedroom_capacity, garbage_disposal, drain_field_type, notes}';;
