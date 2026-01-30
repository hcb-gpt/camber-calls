-- Create trigram index for fast fuzzy search
CREATE INDEX IF NOT EXISTS idx_project_aliases_alias_trgm 
ON project_aliases USING GIN (alias gin_trgm_ops);

-- Create function to find fuzzy alias matches
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
) AS $$
BEGIN
  RETURN QUERY
  WITH matches AS (
    SELECT 
      pa.project_id,
      p.name as project_name,
      pa.alias,
      -- Determine match type and score
      CASE 
        WHEN LOWER(pa.alias) = LOWER(search_term) THEN 'exact'
        WHEN LOWER(pa.alias) LIKE LOWER(search_term) || '%' THEN 'prefix'
        WHEN similarity(LOWER(pa.alias), LOWER(search_term)) >= similarity_threshold THEN 'trigram'
        WHEN levenshtein(LOWER(pa.alias), LOWER(search_term)) <= levenshtein_max THEN 'levenshtein'
        WHEN soundex(pa.alias) = soundex(search_term) THEN 'soundex'
        WHEN dmetaphone(pa.alias) = dmetaphone(search_term) THEN 'metaphone'
        ELSE NULL
      END as match_type,
      CASE 
        WHEN LOWER(pa.alias) = LOWER(search_term) THEN 1.0
        WHEN LOWER(pa.alias) LIKE LOWER(search_term) || '%' THEN 0.95
        WHEN similarity(LOWER(pa.alias), LOWER(search_term)) >= similarity_threshold 
          THEN similarity(LOWER(pa.alias), LOWER(search_term))
        WHEN levenshtein(LOWER(pa.alias), LOWER(search_term)) <= levenshtein_max 
          THEN 1.0 - (levenshtein(LOWER(pa.alias), LOWER(search_term))::FLOAT / 5.0)
        WHEN soundex(pa.alias) = soundex(search_term) THEN 0.7
        WHEN dmetaphone(pa.alias) = dmetaphone(search_term) THEN 0.65
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
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION find_fuzzy_alias_matches IS 
'Finds project aliases matching a search term using trigram similarity, Levenshtein distance, Soundex, and Double Metaphone. Returns matches with type and confidence score.';;
