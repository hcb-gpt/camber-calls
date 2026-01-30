
-- Add floats_between_projects boolean to contacts table
-- Used to flag contacts (like internal staff) who work across multiple projects
-- and should not have affinity-based attribution
ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS floats_between_projects BOOLEAN DEFAULT false;

COMMENT ON COLUMN contacts.floats_between_projects IS 'True for contacts who work across multiple projects (internal staff, floaters). Attribution should use transcript-first logic, not affinity.';
;
