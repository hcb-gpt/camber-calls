-- Fix v3: Check if first name appears with a DIFFERENT last name in transcript
-- Problem: "Randy Booth" in transcript still matched "Randy Bryan" because Randy was unambiguous in candidate pool
-- Solution: If "firstname lastname" appears where lastname != our candidate's lastname, skip the match

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
      LOWER(c.name) as full_name_lower,
      LOWER(SPLIT_PART(c.name, ' ', 1)) as first_name,
      LOWER(SPLIT_PART(c.name, ' ', 2)) as last_name,
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
  -- Get ALL contacts with matching first name (including internal) to detect conflicts
  all_contacts_same_first AS (
    SELECT 
      LOWER(SPLIT_PART(c.name, ' ', 1)) as first_name,
      LOWER(SPLIT_PART(c.name, ' ', 2)) as last_name,
      LOWER(c.name) as full_name
    FROM contacts c
    WHERE LENGTH(SPLIT_PART(c.name, ' ', 1)) >= 4
  ),
  matches AS (
    SELECT 
      p.id as project_id,
      p.name as project_name,
      'mentioned_contact_affinity'::TEXT as source,
      cap.contact_name as mentioned_contact,
      cap.max_weight::FLOAT as contact_affinity,
      CASE
        -- Full name appears in transcript (best match)
        WHEN v_transcript_lower LIKE '%' || cap.full_name_lower || '%' THEN 100
        -- First name + last name both appear (high confidence)
        WHEN cap.last_name != '' 
          AND LENGTH(cap.last_name) >= 3
          AND v_transcript_lower LIKE '%' || cap.first_name || '%'
          AND v_transcript_lower LIKE '%' || cap.last_name || '%' THEN 80
        -- First name only - BUT check if first name appears with a DIFFERENT last name
        WHEN LENGTH(cap.first_name) >= 4
          AND v_transcript_lower LIKE '%' || cap.first_name || '%'
          -- Make sure no OTHER contact with same first name has their full name in transcript
          AND NOT EXISTS (
            SELECT 1 FROM all_contacts_same_first acsf
            WHERE acsf.first_name = cap.first_name
              AND acsf.last_name != cap.last_name
              AND acsf.last_name != ''
              AND v_transcript_lower LIKE '%' || acsf.full_name || '%'
          ) THEN 60
        ELSE 0
      END as match_quality
    FROM contact_affinity_profile cap
    JOIN projects p ON cap.top_project_id = p.id
    WHERE 
      NOT COALESCE(cap.floats_between_projects, false)
      AND p.status IN ('active', 'warranty', 'pre-construction')
  )
  SELECT DISTINCT ON (m.project_id)
    m.project_id,
    m.project_name,
    m.source,
    m.mentioned_contact,
    m.contact_affinity
  FROM matches m
  WHERE m.match_quality > 0
  ORDER BY m.project_id, m.match_quality DESC, m.contact_affinity DESC;
END;
$$;

COMMENT ON FUNCTION expand_candidates_from_mentions IS 
'v3: Scans transcript for contact names with concentrated project affinity.
Fixed: If first name appears with a DIFFERENT last name (e.g., "randy booth"), 
we do not match a different contact (e.g., "Randy Bryan").';;
