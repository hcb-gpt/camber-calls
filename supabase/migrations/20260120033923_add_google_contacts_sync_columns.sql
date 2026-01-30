
-- Add columns for Google Contacts sync tracking
ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS google_contact_id TEXT,
ADD COLUMN IF NOT EXISTS google_synced_at TIMESTAMPTZ;

-- Index for finding unsynced contacts
CREATE INDEX IF NOT EXISTS idx_contacts_google_sync 
ON contacts (google_synced_at, updated_at) 
WHERE google_contact_id IS NOT NULL;

COMMENT ON COLUMN contacts.google_contact_id IS 'Google People API resourceName (e.g., people/c12345678)';
COMMENT ON COLUMN contacts.google_synced_at IS 'Last successful sync to Google Contacts';
;
