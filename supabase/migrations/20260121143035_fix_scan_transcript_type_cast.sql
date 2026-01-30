
-- Fix type casting issue
DROP FUNCTION IF EXISTS scan_transcript_for_projects(text, double precision, integer) CASCADE;

CREATE OR REPLACE FUNCTION scan_transcript_for_projects(
  transcript_text TEXT,
  similarity_threshold DOUBLE PRECISION DEFAULT 0.4,
  min_alias_length INTEGER DEFAULT 4
)
RETURNS TABLE(
  project_id UUID,
  project_name TEXT,
  matched_term TEXT,
  matched_alias TEXT,
  match_type TEXT,
  score DOUBLE PRECISION
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_transcript_lower TEXT;
BEGIN
  -- Normalize transcript for matching
  v_transcript_lower := LOWER(transcript_text);
  
  -- CORRECT DIRECTION: For each alias, check if it appears in transcript
  RETURN QUERY
  WITH alias_candidates AS (
    SELECT 
      pa.project_id,
      p.name as project_name,
      pa.alias,
      pa.alias_type,
      pa.confidence
    FROM project_aliases pa
    JOIN projects p ON pa.project_id = p.id
    WHERE LENGTH(pa.alias) >= min_alias_length
      AND p.status IN ('active', 'warranty', 'pre-construction')
  )
  SELECT DISTINCT ON (ac.project_id, ac.alias)
    ac.project_id,
    ac.project_name,
    ac.alias as matched_term,
    ac.alias as matched_alias,
    CASE
      -- Exact word boundary match
      WHEN v_transcript_lower ~ ('\y' || LOWER(ac.alias) || '\y') THEN 'exact'
      -- Substring match (less strict)
      WHEN v_transcript_lower LIKE '%' || LOWER(ac.alias) || '%' THEN 'substring'
      ELSE 'none'
    END::TEXT as match_type,
    CASE
      WHEN v_transcript_lower ~ ('\y' || LOWER(ac.alias) || '\y') THEN 1.0::DOUBLE PRECISION
      WHEN v_transcript_lower LIKE '%' || LOWER(ac.alias) || '%' THEN 0.9::DOUBLE PRECISION
      ELSE 0.0::DOUBLE PRECISION
    END as score
  FROM alias_candidates ac
  WHERE 
    -- Only return matches that actually appear in transcript
    v_transcript_lower LIKE '%' || LOWER(ac.alias) || '%'
  ORDER BY ac.project_id, ac.alias, score DESC;
END;
$function$;
;
