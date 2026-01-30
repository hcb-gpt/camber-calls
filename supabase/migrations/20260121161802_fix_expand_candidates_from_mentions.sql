CREATE OR REPLACE FUNCTION expand_candidates_from_mentions(transcript_text TEXT)
RETURNS TABLE (
  project_id UUID,
  project_name TEXT,
  source TEXT,
  mentioned_contact TEXT,
  contact_affinity FLOAT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_transcript_lower TEXT;
BEGIN
  v_transcript_lower := LOWER(transcript_text);
  
  RETURN QUERY
  WITH contact_affinity_profile AS (
    SELECT 
      c.id as contact_id,
      c.name as contact_name,
      LOWER(SPLIT_PART(c.name, ' ', 1)) as first_name,
      c.floats_between_projects,
      COUNT(DISTINCT cpa.project_id) as total_projects,
      MAX(cpa.weight) as max_weight,
      (SELECT cpa2.project_id 
       FROM correspondent_project_affinity cpa2 
       WHERE cpa2.contact_id = c.id 
       ORDER BY cpa2.weight DESC LIMIT 1) as top_project_id
    FROM contacts c
    JOIN correspondent_project_affinity cpa ON c.id = cpa.contact_id
    WHERE c.contact_type IN ('subcontractor', 'vendor', 'client')
    GROUP BY c.id, c.name, c.floats_between_projects
    HAVING (
      MAX(cpa.weight) >= 0.9
      OR COUNT(DISTINCT cpa.project_id) = 1
    )
  ),
  matches AS (
    SELECT 
      p.id as project_id,
      p.name as project_name,
      'mentioned_contact_affinity'::TEXT as source,
      cap.contact_name as mentioned_contact,
      cap.max_weight::FLOAT as contact_affinity
    FROM contact_affinity_profile cap
    JOIN projects p ON cap.top_project_id = p.id
    WHERE 
      v_transcript_lower LIKE '%' || cap.first_name || '%'
      AND LENGTH(cap.first_name) >= 4
      AND NOT COALESCE(cap.floats_between_projects, false)
      AND p.status IN ('active', 'warranty', 'pre-construction')
  )
  SELECT DISTINCT ON (m.project_id)
    m.project_id,
    m.project_name,
    m.source,
    m.mentioned_contact,
    m.contact_affinity
  FROM matches m
  ORDER BY m.project_id, m.contact_affinity DESC;
END;
$$;;
