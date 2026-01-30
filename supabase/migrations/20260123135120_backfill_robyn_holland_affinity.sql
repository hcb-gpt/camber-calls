-- Backfill affinity edge for Robyn Holland (project_contact exists but affinity missing)
INSERT INTO correspondent_project_affinity (id, contact_id, project_id, weight, source, created_at, updated_at)
SELECT
  gen_random_uuid(),
  pc.contact_id,
  pc.project_id,
  0.8,
  'project_contacts_backfill',
  NOW(),
  NOW()
FROM project_contacts pc
LEFT JOIN correspondent_project_affinity cpa
  ON pc.contact_id = cpa.contact_id AND pc.project_id = cpa.project_id
WHERE cpa.id IS NULL;;
