-- Create affinity records for the 47 project_contacts missing them
INSERT INTO correspondent_project_affinity (contact_id, project_id, weight, source)
SELECT pc.contact_id, pc.project_id, 0.8, 'project_contacts_sync'
FROM project_contacts pc
WHERE NOT EXISTS (
  SELECT 1 FROM correspondent_project_affinity cpa
  WHERE cpa.contact_id = pc.contact_id AND cpa.project_id = pc.project_id
)
ON CONFLICT DO NOTHING;;
