-- Add project name stems as aliases (e.g., "Sittler" from "Sittler Residence (Athens)")
-- Extract first word before "Residence" or parenthesis
INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
SELECT 
  gen_random_uuid(),
  p.id,
  LOWER(TRIM(SPLIT_PART(SPLIT_PART(p.name, ' Residence', 1), ' (', 1))),
  'project_name_stem',
  'auto_generated',
  0.95,
  NOW(),
  'data_migration_2026-01-21'
FROM projects p
WHERE p.status = 'active'
  AND p.name LIKE '% Residence%'
  AND NOT EXISTS (
    SELECT 1 FROM project_aliases pa 
    WHERE pa.project_id = p.id 
    AND LOWER(pa.alias) = LOWER(TRIM(SPLIT_PART(SPLIT_PART(p.name, ' Residence', 1), ' (', 1)))
  )
ON CONFLICT DO NOTHING;;
