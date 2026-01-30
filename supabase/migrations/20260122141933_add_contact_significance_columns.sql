
-- Add columns for contact significance tracking
ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS total_transcript_chars INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS is_key_contact BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS key_contact_reason TEXT;

-- Add comment explaining is_key_contact
COMMENT ON COLUMN contacts.is_key_contact IS 'Manual override for contacts who are important but dont show up in call data (e.g., in-person conversations, family)';
COMMENT ON COLUMN contacts.total_transcript_chars IS 'Cumulative transcript length - captures significance of conversations, not just frequency';
;
