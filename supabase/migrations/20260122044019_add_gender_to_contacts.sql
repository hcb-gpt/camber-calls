-- Add gender field to contacts table
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS gender text;

-- Add constraint for valid values
ALTER TABLE contacts ADD CONSTRAINT contacts_gender_check 
  CHECK (gender IS NULL OR gender IN ('male', 'female', 'other'));

-- Add comment
COMMENT ON COLUMN contacts.gender IS 'Contact gender: male, female, other. Used for pronoun selection in AI outputs.';;
