
-- Fix: Exclude speaker labels from alias matching
-- Speaker pattern: "First Last:" at start of line

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
  v_transcript_clean TEXT;
BEGIN
  -- Remove speaker labels (pattern: "Name Name:" at line start)
  -- This prevents matching "Sittler" from "Zachary Sittler:" speaker labels
  v_transcript_clean := REGEXP_REPLACE(
    transcript_text,
    '(^|\n)\s*[A-Z][a-z]+(\s+[A-Z][a-z]+)*\s*:',  -- "First Last:" pattern
    '\1',
    'g'
  );
  
  -- Normalize for matching
  v_transcript_clean := LOWER(v_transcript_clean);
  
  -- CORRECT DIRECTION: For each alias, check if it appears in cleaned transcript
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
      WHEN v_transcript_clean ~ ('\y' || LOWER(ac.alias) || '\y') THEN 'exact'
      WHEN v_transcript_clean LIKE '%' || LOWER(ac.alias) || '%' THEN 'substring'
      ELSE 'none'
    END::TEXT as match_type,
    CASE
      WHEN v_transcript_clean ~ ('\y' || LOWER(ac.alias) || '\y') THEN 1.0::DOUBLE PRECISION
      WHEN v_transcript_clean LIKE '%' || LOWER(ac.alias) || '%' THEN 0.9::DOUBLE PRECISION
      ELSE 0.0::DOUBLE PRECISION
    END as score
  FROM alias_candidates ac
  WHERE 
    v_transcript_clean LIKE '%' || LOWER(ac.alias) || '%'
  ORDER BY ac.project_id, ac.alias, score DESC;
END;
$function$;

COMMENT ON FUNCTION scan_transcript_for_projects IS 
'Scans transcript for known project aliases. 
Direction: aliases → transcript.
Excludes speaker labels (e.g., "Zachary Sittler:") to avoid false matches.';
;
