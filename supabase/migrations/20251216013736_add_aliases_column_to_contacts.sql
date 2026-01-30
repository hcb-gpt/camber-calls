-- Add aliases column to contacts table to match projects structure
ALTER TABLE contacts 
ADD COLUMN aliases text[] DEFAULT '{}';

-- Add comment explaining the column's purpose
COMMENT ON COLUMN contacts.aliases IS 
'Array of name variations, misspellings, nicknames, and common references (e.g., ["Joe Hurley", "Joseph Hurley", "J Hurley"]). Used for fuzzy matching in message/interaction analysis.';

-- Add index for array searches
CREATE INDEX idx_contacts_aliases_gin ON contacts USING GIN (aliases);
;
