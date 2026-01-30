-- Migration: Seed correspondent_project_affinity from project_clients
-- Removes cold-start failure for client calls immediately
-- Per STRAT: clients are high-confidence signal, weight=1.0

INSERT INTO correspondent_project_affinity 
  (id, contact_id, project_id, weight, confirmation_count, source, created_at, updated_at)
SELECT 
  gen_random_uuid(),
  pc.contact_id,
  pc.project_id,
  1.0,                           -- high confidence for explicit client assignment
  1,                             -- baseline confirmation
  'project_clients',             -- provenance
  now(),
  now()
FROM project_clients pc
ON CONFLICT (contact_id, project_id) DO NOTHING;;
