-- Function to expand project candidates based on speaker floater affinities
CREATE OR REPLACE FUNCTION expand_candidates_from_speakers(transcript_text TEXT)
RETURNS TABLE(
  project_id UUID,
  project_name TEXT,
  source TEXT,
  source_speaker TEXT,
  confidence FLOAT
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    p.id as project_id,
    p.name as project_name,
    'speaker_floater_expansion'::TEXT as source,
    rs.speaker_name as source_speaker,
    CASE 
      WHEN rs.contact_type = 'internal' THEN 0.7
      WHEN rs.contact_type = 'client' THEN 0.95
      ELSE 0.6
    END as confidence
  FROM resolve_transcript_speakers(transcript_text) rs
  CROSS JOIN LATERAL UNNEST(rs.affiliated_project_ids) as pid(project_id)
  JOIN projects p ON p.id = pid.project_id
  WHERE rs.affiliated_project_ids IS NOT NULL
  ORDER BY confidence DESC, p.name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION expand_candidates_from_speakers IS 
'Expands project candidates by extracting speakers from transcript, resolving them to contacts, and returning their affiliated projects. Floaters expand to all their projects.';;
