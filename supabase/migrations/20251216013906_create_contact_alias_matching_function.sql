-- Create a function to find contacts by name or alias
CREATE OR REPLACE FUNCTION find_contact_by_name_or_alias(search_term text)
RETURNS TABLE (
    contact_id uuid,
    contact_name text,
    contact_phone text,
    contact_type text,
    company text,
    match_type text,
    matched_value text
) AS $$
BEGIN
    RETURN QUERY
    -- Match on primary name (exact or partial)
    SELECT 
        c.id,
        c.name,
        c.phone,
        c.contact_type,
        c.company,
        'primary_name'::text as match_type,
        c.name as matched_value
    FROM contacts c
    WHERE c.name ILIKE '%' || search_term || '%'
    
    UNION
    
    -- Match on any alias
    SELECT 
        c.id,
        c.name,
        c.phone,
        c.contact_type,
        c.company,
        'alias'::text as match_type,
        alias as matched_value
    FROM contacts c
    CROSS JOIN LATERAL unnest(c.aliases) as alias
    WHERE alias ILIKE '%' || search_term || '%'
    
    ORDER BY match_type, contact_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION find_contact_by_name_or_alias(text) IS 
'Search for contacts by name or any registered alias. Returns match_type to indicate whether match was on primary name or an alias.';


-- Create a function to check if a text string matches any contact
CREATE OR REPLACE FUNCTION match_text_to_contact(input_text text)
RETURNS TABLE (
    contact_id uuid,
    contact_name text,
    contact_phone text,
    matched_alias text,
    match_confidence numeric
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.phone,
        alias,
        CASE 
            WHEN input_text ILIKE '%' || c.name || '%' THEN 1.0
            WHEN input_text ILIKE '%' || alias || '%' THEN 0.9
            ELSE 0.0
        END as confidence
    FROM contacts c
    CROSS JOIN LATERAL unnest(ARRAY[c.name] || COALESCE(c.aliases, '{}')) as alias
    WHERE input_text ILIKE '%' || alias || '%'
    ORDER BY confidence DESC, c.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION match_text_to_contact(text) IS 
'Given a text string, find all contacts whose name or aliases appear in the text. Returns confidence score.';
;
