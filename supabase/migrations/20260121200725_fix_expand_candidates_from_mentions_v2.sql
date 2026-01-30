-- Fix: Improve expand_candidates_from_mentions to avoid first-name collisions
-- Problem: "Randy Booth" in transcript matched to "Randy Bryan" because only first name was checked
-- Solution: Prefer full name matches, skip when multiple contacts share same first name

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
  -- Count how many candidate contacts share each first name
  first_name_counts AS (
    SELECT first_name, COUNT(*) as cnt
    FROM contact_affinity_profile
    GROUP BY first_name
  ),
  matches AS (
    SELECT 
      p.id as project_id,
      p.name as project_name,
      'mentioned_contact_affinity'::TEXT as source,
      cap.contact_name as mentioned_contact,
      cap.max_weight::FLOAT as contact_affinity,
      -- Match quality: full name > first+last > first only (if unambiguous)
      CASE
        -- Full name appears in transcript (best match)
        WHEN v_transcript_lower LIKE '%' || cap.full_name_lower || '%' THEN 100
        -- First name + last name both appear (not necessarily together)
        WHEN cap.last_name != '' 
          AND LENGTH(cap.last_name) >= 3
          AND v_transcript_lower LIKE '%' || cap.first_name || '%'
          AND v_transcript_lower LIKE '%' || cap.last_name || '%' THEN 80
        -- First name only, but NO OTHER contacts share this first name
        WHEN fnc.cnt = 1 
          AND LENGTH(cap.first_name) >= 4
          AND v_transcript_lower LIKE '%' || cap.first_name || '%' THEN 60
        ELSE 0
      END as match_quality
    FROM contact_affinity_profile cap
    JOIN projects p ON cap.top_project_id = p.id
    JOIN first_name_counts fnc ON fnc.first_name = cap.first_name
    WHERE 
      NOT COALESCE(cap.floats_between_projects, false)
      AND p.status IN ('active', 'warranty', 'pre-construction')
      -- At least some form of name appears
      AND (
        v_transcript_lower LIKE '%' || cap.full_name_lower || '%'
        OR (cap.last_name != '' AND v_transcript_lower LIKE '%' || cap.first_name || '%' AND v_transcript_lower LIKE '%' || cap.last_name || '%')
        OR (fnc.cnt = 1 AND LENGTH(cap.first_name) >= 4 AND v_transcript_lower LIKE '%' || cap.first_name || '%')
      )
  )
  SELECT DISTINCT ON (m.project_id)
    m.project_id,
    m.project_name,
    m.source,
    m.mentioned_contact,
    m.contact_affinity
  FROM matches m
  WHERE m.match_quality > 0  -- Only return actual matches
  ORDER BY m.project_id, m.match_quality DESC, m.contact_affinity DESC;
END;
$$;

COMMENT ON FUNCTION expand_candidates_from_mentions IS 
'v2: Scans transcript for contact names with concentrated project affinity.
Fixed: Avoids first-name collisions (e.g., "Randy Booth" no longer matches "Randy Bryan").
Match priority: full name > first+last > first only (if unambiguous).';;
