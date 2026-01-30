-- Add company_aliases column for vendor company name variations
ALTER TABLE contacts 
ADD COLUMN company_aliases text[] DEFAULT '{}';

COMMENT ON COLUMN contacts.company_aliases IS 
'Array of company name variations (e.g., ["Crossed Chisels", "Crossed Chisels LLC", "Crossed Chisels, LLC"])';

CREATE INDEX idx_contacts_company_aliases_gin ON contacts USING GIN (company_aliases);

-- Create a view to help discover potential new aliases from message patterns
CREATE OR REPLACE VIEW v_alias_discovery_candidates AS
WITH known_aliases AS (
    -- Get all current names and aliases  
    SELECT name as known_term, name as contact_name, 'primary' as source FROM contacts
    UNION ALL
    SELECT unnest(aliases), name, 'alias' FROM contacts WHERE aliases != '{}'
    UNION ALL
    SELECT unnest(company_aliases), name, 'company_alias' FROM contacts WHERE company_aliases != '{}'
)
SELECT 
    c.id,
    c.name,
    c.contact_type,
    c.company,
    c.phone,
    cardinality(c.aliases) as alias_count,
    c.aliases,
    c.company_aliases,
    c.notes,
    -- Flag contacts that might need more aliases
    CASE 
        WHEN c.notes LIKE '%Name variations:%' AND cardinality(c.aliases) = 0 THEN 'HAS_NOTES_VARIATIONS'
        WHEN c.company IS NOT NULL AND cardinality(c.company_aliases) = 0 THEN 'NEEDS_COMPANY_ALIASES'
        WHEN cardinality(c.aliases) = 0 THEN 'NO_ALIASES'
        ELSE 'OK'
    END as alias_status
FROM contacts c
WHERE c.contact_type NOT IN ('spam')
ORDER BY 
    CASE 
        WHEN c.notes LIKE '%Name variations:%' AND cardinality(c.aliases) = 0 THEN 1
        WHEN c.company IS NOT NULL AND cardinality(c.company_aliases) = 0 THEN 2
        WHEN cardinality(c.aliases) = 0 THEN 3
        ELSE 4
    END,
    c.name;

COMMENT ON VIEW v_alias_discovery_candidates IS 
'Identifies contacts that may need alias additions based on notes content, company presence, or missing aliases';
;
