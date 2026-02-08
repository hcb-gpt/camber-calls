-- Fix overly permissive RLS policies on journal/belief tables
-- Replace "Service role full access" with proper "Service role only" (includes WITH CHECK)
-- Applied from browser session; synced to git for git-first compliance.

-- Fix adapter_status: drop permissive, add proper
DROP POLICY IF EXISTS "Service role full access" ON public.adapter_status;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'adapter_status' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.adapter_status
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix belief_assumptions
DROP POLICY IF EXISTS "Service role full access" ON public.belief_assumptions;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'belief_assumptions' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.belief_assumptions
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix belief_claims
DROP POLICY IF EXISTS "Service role full access" ON public.belief_claims;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'belief_claims' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.belief_claims
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix belief_conflicts
DROP POLICY IF EXISTS "Service role full access" ON public.belief_conflicts;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'belief_conflicts' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.belief_conflicts
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix belief_open_loops
DROP POLICY IF EXISTS "Service role full access" ON public.belief_open_loops;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'belief_open_loops' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.belief_open_loops
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix claim_pointers
DROP POLICY IF EXISTS "Service role full access" ON public.claim_pointers;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'claim_pointers' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.claim_pointers
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix conflict_claims
DROP POLICY IF EXISTS "Service role full access" ON public.conflict_claims;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'conflict_claims' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.conflict_claims
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- Fix loop_pointers
DROP POLICY IF EXISTS "Service role full access" ON public.loop_pointers;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'loop_pointers' AND policyname = 'Service role only') THEN
    CREATE POLICY "Service role only" ON public.loop_pointers
      FOR ALL USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;
