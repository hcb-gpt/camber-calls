SELECT
  now() AS measured_at_utc,
  to_regclass('public.project_facts') IS NOT NULL AS project_facts_table_exists,
  (
    SELECT COUNT(*)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'project_facts_as_of'
  ) AS project_facts_as_of_fn_count;

SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'project_facts'
ORDER BY ordinal_position;

SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  pg_get_function_result(p.oid) AS returns
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'project_facts_as_of'
ORDER BY 1, 2;

SELECT
  COUNT(*) AS migration_present
FROM supabase_migrations.schema_migrations
WHERE version = '20260215254000';

