-- Add RLS policies to tables that had RLS enabled but no policies
-- Applied from browser session; synced to git for git-first compliance.
-- Idempotent: uses DO blocks with IF NOT EXISTS checks.

-- api_keys: sensitive credentials, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'api_keys' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.api_keys
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- geo_places: pipeline reference data, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'geo_places' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.geo_places
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- idempotency_keys: pipeline dedup, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'idempotency_keys' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.idempotency_keys
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- pipedream_run_logs: pipeline execution logs, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'pipedream_run_logs' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.pipedream_run_logs
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- project_geo: project geocoding data, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'project_geo' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.project_geo
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- span_place_mentions: pipeline output, service_role only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'span_place_mentions' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.span_place_mentions
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;
