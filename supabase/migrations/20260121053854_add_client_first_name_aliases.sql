-- Add client first names as aliases (unique across projects or same-family multi-project)
INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
SELECT 
  gen_random_uuid(),
  cpa.project_id,
  LOWER(SPLIT_PART(c.name, ' ', 1)),
  'client_first_name',
  'auto_generated',
  0.9,
  NOW(),
  'data_migration_2026-01-21'
FROM contacts c
JOIN correspondent_project_affinity cpa ON c.id = cpa.contact_id
JOIN projects p ON cpa.project_id = p.id
WHERE c.contact_type = 'client'
  AND cpa.weight > 0
  AND SPLIT_PART(c.name, ' ', 1) != ''
  AND NOT EXISTS (
    SELECT 1 FROM project_aliases pa 
    WHERE pa.project_id = cpa.project_id 
    AND LOWER(pa.alias) = LOWER(SPLIT_PART(c.name, ' ', 1))
  )
ON CONFLICT DO NOTHING;;
