INSERT INTO correspondent_project_affinity (id, contact_id, project_id, weight, source, created_at, updated_at)
VALUES (
  gen_random_uuid(),
  'd0a1b2c3-d4e5-f678-90ab-cdef01234567',
  'd8091a15-6a69-4634-8d5b-117abea35aa6',
  0.8,
  'project_contacts_backfill',
  NOW(),
  NOW()
);;
