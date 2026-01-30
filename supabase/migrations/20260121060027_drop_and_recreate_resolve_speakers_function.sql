-- Drop and recreate with improved fuzzy matching
DROP FUNCTION IF EXISTS resolve_transcript_speakers(TEXT);

CREATE OR REPLACE FUNCTION resolve_transcript_speakers(transcript_text TEXT)
RETURNS TABLE(
  speaker_name TEXT,
  contact_id UUID,
  contact_name TEXT,
  contact_type TEXT,
  project_count INT,
  is_floater BOOLEAN,
  affiliated_project_ids UUID[]
) AS $$
BEGIN
  RETURN QUERY
  WITH speakers AS (
    SELECT e.speaker_name
    FROM extract_speakers_from_transcript(transcript_text) e
  ),
  resolved AS (
    SELECT DISTINCT ON (s.speaker_name)
      s.speaker_name,
      c.id as contact_id,
      c.name as contact_name,
      c.contact_type,
      CASE 
        WHEN LOWER(c.name) = LOWER(s.speaker_name) THEN 100
        WHEN c.name ILIKE s.speaker_name || '%' THEN 90
        WHEN c.name ILIKE '%' || SPLIT_PART(s.speaker_name, ' ', 2) THEN 80
        WHEN similarity(c.name, s.speaker_name) > 0.5 THEN 70
        ELSE 0
      END as match_quality
    FROM speakers s
    LEFT JOIN contacts c ON 
      LOWER(c.name) = LOWER(s.speaker_name)
      OR c.name ILIKE s.speaker_name || '%'
      OR (
        SPLIT_PART(c.name, ' ', 2) != '' 
        AND LOWER(SPLIT_PART(c.name, ' ', 2)) = LOWER(SPLIT_PART(s.speaker_name, ' ', 2))
        AND similarity(SPLIT_PART(c.name, ' ', 1), SPLIT_PART(s.speaker_name, ' ', 1)) > 0.3
      )
      OR similarity(c.name, s.speaker_name) > 0.6
    WHERE c.contact_type IN ('internal', 'client', 'subcontractor', 'vendor') OR c.id IS NULL
    ORDER BY s.speaker_name, match_quality DESC
  ),
  with_affinities AS (
    SELECT 
      r.speaker_name,
      r.contact_id,
      r.contact_name,
      r.contact_type,
      COUNT(DISTINCT cpa.project_id)::INT as project_count,
      COUNT(DISTINCT cpa.project_id) > 1 as is_floater,
      ARRAY_AGG(DISTINCT cpa.project_id) FILTER (WHERE cpa.project_id IS NOT NULL) as affiliated_project_ids
    FROM resolved r
    LEFT JOIN correspondent_project_affinity cpa ON r.contact_id = cpa.contact_id
    GROUP BY r.speaker_name, r.contact_id, r.contact_name, r.contact_type
  )
  SELECT 
    wa.speaker_name,
    wa.contact_id,
    wa.contact_name,
    wa.contact_type,
    wa.project_count,
    wa.is_floater,
    wa.affiliated_project_ids
  FROM with_affinities wa
  ORDER BY wa.project_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION resolve_transcript_speakers IS 
'Resolves transcript speaker names to contacts (with fuzzy matching for name variants like Zack/Zachary). Returns project affinities and floater flag.';;
