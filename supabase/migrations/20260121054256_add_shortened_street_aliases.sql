-- Add shortened street name aliases (first 2 words for 3+ word streets, first word for 2-word streets)
INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
VALUES
  -- Hickory Grove Church → "hickory grove" and "hickory"
  (gen_random_uuid(), 'd8091a15-6a69-4634-8d5b-117abea35aa6', 'hickory grove', 'street_name_short', 'auto_generated', 0.85, NOW(), 'data_migration_2026-01-21'),
  (gen_random_uuid(), 'd8091a15-6a69-4634-8d5b-117abea35aa6', 'hickory', 'street_name_short', 'auto_generated', 0.75, NOW(), 'data_migration_2026-01-21'),
  
  -- Downs Creek → "downs"
  (gen_random_uuid(), 'ed8e85a2-c79c-4951-aee1-4e17254c06a0', 'downs', 'street_name_short', 'auto_generated', 0.75, NOW(), 'data_migration_2026-01-21'),
  
  -- New High Shoals → "high shoals" and "new high"
  (gen_random_uuid(), '47cb7720-9495-4187-8220-a8100c3b67aa', 'high shoals', 'street_name_short', 'auto_generated', 0.85, NOW(), 'data_migration_2026-01-21'),
  
  -- Price Mill → "price"
  (gen_random_uuid(), '7ca8829a-72ea-4d60-b0ea-a17d45b6ace3', 'price', 'street_name_short', 'auto_generated', 0.75, NOW(), 'data_migration_2026-01-21'),
  
  -- Red Oak → "red oak" already full, add "oak" 
  (gen_random_uuid(), 'fcd501c7-d983-4f84-a4f6-774ad077c7af', 'oak', 'street_name_short', 'auto_generated', 0.70, NOW(), 'data_migration_2026-01-21'),
  
  -- North Main → "main" (careful - may be generic)
  (gen_random_uuid(), '4d5a7252-f3bb-4e31-80fc-e72a7ec78520', 'main street', 'street_name_short', 'auto_generated', 0.70, NOW(), 'data_migration_2026-01-21')
ON CONFLICT DO NOTHING;;
