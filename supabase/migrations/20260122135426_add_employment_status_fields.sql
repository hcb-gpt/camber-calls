-- Add employment status fields to contacts for proper 1NF
ALTER TABLE contacts 
ADD COLUMN employment_status text CHECK (employment_status IN ('active', 'former', 'contractor', 'seasonal')),
ADD COLUMN employed_from date,
ADD COLUMN employed_until date;

COMMENT ON COLUMN contacts.employment_status IS 'Employment status for internal contacts: active, former, contractor, seasonal';
COMMENT ON COLUMN contacts.employed_from IS 'Start date of employment/engagement';
COMMENT ON COLUMN contacts.employed_until IS 'End date of employment (NULL if still active)';;
