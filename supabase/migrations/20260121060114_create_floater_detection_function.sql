-- Function to list all floaters (contacts with multiple project affinities)
CREATE OR REPLACE FUNCTION list_floaters(min_projects INT DEFAULT 2)
RETURNS TABLE(
  contact_id UUID,
  contact_name TEXT,
  contact_type TEXT,
  project_count INT,
  projects TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id as contact_id,
    c.name as contact_name,
    c.contact_type,
    COUNT(DISTINCT cpa.project_id)::INT as project_count,
    STRING_AGG(DISTINCT p.name, ', ' ORDER BY p.name) as projects
  FROM contacts c
  JOIN correspondent_project_affinity cpa ON c.id = cpa.contact_id
  JOIN projects p ON cpa.project_id = p.id
  WHERE c.contact_type IN ('internal', 'subcontractor', 'vendor')
  GROUP BY c.id, c.name, c.contact_type
  HAVING COUNT(DISTINCT cpa.project_id) >= min_projects
  ORDER BY COUNT(DISTINCT cpa.project_id) DESC, c.name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION list_floaters IS 
'Lists contacts who work across multiple projects (floaters). Default: 2+ projects.';;
