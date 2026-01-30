-- Drop and recreate the function with fixed ORDER BY
DROP FUNCTION IF EXISTS find_contact_by_name_or_alias(text);

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
    WITH matches AS (
        -- Match on primary name (exact or partial)
        SELECT 
            c.id,
            c.name,
            c.phone,
            c.contact_type,
            c.company,
            'primary_name'::text as mtype,
            c.name as mvalue
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
            'alias'::text as mtype,
            alias as mvalue
        FROM contacts c
        CROSS JOIN LATERAL unnest(c.aliases) as alias
        WHERE alias ILIKE '%' || search_term || '%'
    )
    SELECT * FROM matches ORDER BY mtype, name;
END;
$$ LANGUAGE plpgsql;
;
