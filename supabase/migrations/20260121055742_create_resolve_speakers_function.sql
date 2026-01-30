-- Function to resolve transcript speakers to contacts and get their project affinities
CREATE OR REPLACE FUNCTION resolve_transcript_speakers(transcript_text TEXT)
RETURNS TABLE(
  speaker_name TEXT,
  contact_id UUID,
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
    SELECT 
      s.speaker_name,
      c.id as contact_id,
      c.contact_type,
      COUNT(DISTINCT cpa.project_id)::INT as project_count,
      COUNT(DISTINCT cpa.project_id) > 1 as is_floater,
      ARRAY_AGG(DISTINCT cpa.project_id) FILTER (WHERE cpa.project_id IS NOT NULL) as affiliated_project_ids
    FROM speakers s
    LEFT JOIN contacts c ON LOWER(c.name) = LOWER(s.speaker_name)
    LEFT JOIN correspondent_project_affinity cpa ON c.id = cpa.contact_id
    GROUP BY s.speaker_name, c.id, c.contact_type
  )
  SELECT 
    r.speaker_name,
    r.contact_id,
    r.contact_type,
    r.project_count,
    r.is_floater,
    r.affiliated_project_ids
  FROM resolved r
  ORDER BY r.project_count DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION resolve_transcript_speakers IS 
'Resolves transcript speaker names to contacts and returns their project affinities. Flags floaters (internal contacts with multiple projects).';;
