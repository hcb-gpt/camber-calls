-- Seed correspondent_project_affinity from project_contacts (vendors)
-- Weight 0.7 for inferred assignments (lower than clients at 1.0)
-- This ensures candidate project selection has vendor coverage

INSERT INTO correspondent_project_affinity 
  (id, contact_id, project_id, weight, confirmation_count, source, created_at, updated_at)
SELECT 
  gen_random_uuid(),
  pc.contact_id,
  pc.project_id,
  0.7,                           -- medium-high confidence for assignment
  0,                             -- no confirmations yet
  'project_contacts_inferred',   -- provenance
  now(),
  now()
FROM project_contacts pc
WHERE pc.source = 'data_inferred'
ON CONFLICT (contact_id, project_id) DO NOTHING;;
