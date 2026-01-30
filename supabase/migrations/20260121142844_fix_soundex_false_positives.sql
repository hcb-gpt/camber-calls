
-- Fix soundex false positives by requiring length similarity
-- "bronze" should NOT match "barn shop" just because they sound vaguely similar

CREATE OR REPLACE FUNCTION find_fuzzy_alias_matches(
  search_term TEXT,
  similarity_threshold FLOAT DEFAULT 0.3,
  levenshtein_max INT DEFAULT 2
)
RETURNS TABLE(
  project_id UUID,
  project_name TEXT,
  alias TEXT,
  match_type TEXT,
  score FLOAT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH matches AS (
    SELECT 
      pa.project_id,
      p.name as project_name,
      pa.alias,
      -- Determine match type and score
      -- Priority: exact > prefix > trigram > levenshtein > soundex > metaphone
      CASE 
        WHEN LOWER(pa.alias) = LOWER(search_term) THEN 'exact'
        WHEN LOWER(pa.alias) LIKE LOWER(search_term) || '%' THEN 'prefix'
        WHEN similarity(LOWER(pa.alias), LOWER(search_term)) >= similarity_threshold THEN 'trigram'
        WHEN levenshtein(LOWER(pa.alias), LOWER(search_term)) <= levenshtein_max THEN 'levenshtein'
        -- SOUNDEX: only if lengths are within 50% of each other (prevents "bronze" → "barn shop")
        WHEN soundex(pa.alias) = soundex(search_term) 
             AND ABS(LENGTH(pa.alias) - LENGTH(search_term)) <= GREATEST(LENGTH(pa.alias), LENGTH(search_term)) * 0.5
             AND similarity(LOWER(pa.alias), LOWER(search_term)) >= 0.2
             THEN 'soundex'
        -- METAPHONE: same constraints
        WHEN dmetaphone(pa.alias) = dmetaphone(search_term)
             AND ABS(LENGTH(pa.alias) - LENGTH(search_term)) <= GREATEST(LENGTH(pa.alias), LENGTH(search_term)) * 0.5
             AND similarity(LOWER(pa.alias), LOWER(search_term)) >= 0.2
             THEN 'metaphone'
        ELSE NULL
      END as match_type,
      CASE 
        WHEN LOWER(pa.alias) = LOWER(search_term) THEN 1.0
        WHEN LOWER(pa.alias) LIKE LOWER(search_term) || '%' THEN 0.95
        WHEN similarity(LOWER(pa.alias), LOWER(search_term)) >= similarity_threshold 
          THEN similarity(LOWER(pa.alias), LOWER(search_term))
        WHEN levenshtein(LOWER(pa.alias), LOWER(search_term)) <= levenshtein_max 
          THEN 1.0 - (levenshtein(LOWER(pa.alias), LOWER(search_term))::FLOAT / 5.0)
        -- Lower soundex score to 0.5 (was 0.7) - it's a weak signal
        WHEN soundex(pa.alias) = soundex(search_term) 
             AND ABS(LENGTH(pa.alias) - LENGTH(search_term)) <= GREATEST(LENGTH(pa.alias), LENGTH(search_term)) * 0.5
             AND similarity(LOWER(pa.alias), LOWER(search_term)) >= 0.2
             THEN 0.5
        -- Lower metaphone score to 0.45 (was 0.65)
        WHEN dmetaphone(pa.alias) = dmetaphone(search_term)
             AND ABS(LENGTH(pa.alias) - LENGTH(search_term)) <= GREATEST(LENGTH(pa.alias), LENGTH(search_term)) * 0.5
             AND similarity(LOWER(pa.alias), LOWER(search_term)) >= 0.2
             THEN 0.45
        ELSE 0
      END as score
    FROM project_aliases pa
    JOIN projects p ON pa.project_id = p.id
    WHERE 
      -- Quick filter using trigram index
      pa.alias % search_term
      OR LOWER(pa.alias) = LOWER(search_term)
      OR LOWER(pa.alias) LIKE LOWER(search_term) || '%'
      OR soundex(pa.alias) = soundex(search_term)
      OR dmetaphone(pa.alias) = dmetaphone(search_term)
  )
  SELECT m.project_id, m.project_name, m.alias, m.match_type, m.score
  FROM matches m
  WHERE m.match_type IS NOT NULL
  ORDER BY m.score DESC, m.alias;
END;
$$;

COMMENT ON FUNCTION find_fuzzy_alias_matches IS 
'Find project aliases matching a search term using multiple strategies.
v2: Fixed soundex/metaphone false positives by requiring:
  1. Length similarity (within 50%)
  2. Minimum trigram similarity (0.2)
  3. Lowered phonetic match scores (0.5 soundex, 0.45 metaphone)
This prevents "bronze" from matching "barn shop" while still allowing 
legitimate phonetic matches like "shailin" → "shayelyn"';
;
