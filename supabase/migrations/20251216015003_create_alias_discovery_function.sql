-- Create function to suggest new aliases based on message content analysis
-- This helps discover variations you haven't captured yet

CREATE OR REPLACE FUNCTION suggest_alias_additions(sample_text text)
RETURNS TABLE (
    contact_id uuid,
    contact_name text,
    current_aliases text[],
    potential_new_alias text,
    match_context text,
    recommendation text
) 
SET search_path = public
AS $$
DECLARE
    words text[];
    word text;
BEGIN
    -- Extract capitalized words that might be names
    words := ARRAY(
        SELECT DISTINCT match[1]
        FROM regexp_matches(sample_text, '\m([A-Z][a-z]+)\M', 'g') as match
        WHERE length(match[1]) > 2
    );
    
    -- For each word, check if it's close to but not exactly matching a contact
    RETURN QUERY
    WITH potential_matches AS (
        SELECT 
            c.id,
            c.name,
            c.aliases,
            w.word as candidate,
            -- Simple similarity check
            CASE
                WHEN c.name ILIKE '%' || w.word || '%' THEN 'name_substring'
                WHEN w.word ILIKE ANY(c.aliases) THEN 'already_alias'
                WHEN levenshtein(lower(w.word), lower(split_part(c.name, ' ', 1))) <= 2 THEN 'fuzzy_first'
                WHEN levenshtein(lower(w.word), lower(split_part(c.name, ' ', 2))) <= 2 THEN 'fuzzy_last'
                ELSE NULL
            END as match_type
        FROM contacts c
        CROSS JOIN unnest(words) as w(word)
        WHERE c.contact_type NOT IN ('spam')
    )
    SELECT 
        pm.id,
        pm.name,
        pm.aliases,
        pm.candidate,
        pm.match_type,
        CASE 
            WHEN pm.match_type = 'already_alias' THEN 'Already tracked'
            WHEN pm.match_type = 'name_substring' THEN 'Consider adding as alias'
            WHEN pm.match_type IN ('fuzzy_first', 'fuzzy_last') THEN 'Possible misspelling - review'
            ELSE 'No action'
        END as rec
    FROM potential_matches pm
    WHERE pm.match_type IS NOT NULL
    AND pm.match_type != 'already_alias'
    ORDER BY pm.name, pm.candidate;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION suggest_alias_additions(text) IS 
'Analyzes sample text to suggest potential new aliases based on fuzzy matching. 
Pass in message content to discover name variations not yet captured in aliases.';

-- Also create a simpler collision-check function
CREATE OR REPLACE FUNCTION check_alias_collision(proposed_alias text)
RETURNS TABLE (
    contact_name text,
    contact_type text,
    match_source text
)
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT c.name, c.contact_type, 'primary_name'::text
    FROM contacts c 
    WHERE c.name ILIKE '%' || proposed_alias || '%'
    UNION ALL
    SELECT c.name, c.contact_type, 'alias'::text
    FROM contacts c, unnest(c.aliases) as a
    WHERE a ILIKE '%' || proposed_alias || '%'
    UNION ALL  
    SELECT c.name, c.contact_type, 'company_alias'::text
    FROM contacts c, unnest(c.company_aliases) as ca
    WHERE ca ILIKE '%' || proposed_alias || '%';
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_alias_collision(text) IS 
'Before adding a new alias, check if it would collide with existing contacts';
;
