-- Fix pg_cron wiring for edge-triggered jobs and add morning-digest cron trigger.
-- Replaces invalid psql-placeholder commands (:'supabase_url') with runtime-safe SQL helpers.

CREATE OR REPLACE FUNCTION public.get_pipeline_credential(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT trim(both '"' FROM pc.config_value::text)
  FROM public.pipeline_config pc
  WHERE pc.scope = 'credentials'
    AND pc.config_key = p_key
  ORDER BY pc.updated_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_supabase_ref_from_service_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH raw AS (
    SELECT public.get_pipeline_credential('SUPABASE_SERVICE_ROLE_KEY') AS jwt
  ),
  payload AS (
    SELECT split_part(jwt, '.', 2) AS b64url
    FROM raw
    WHERE jwt IS NOT NULL
      AND jwt <> ''
      AND position('.' IN jwt) > 0
  ),
  normalized AS (
    SELECT
      translate(b64url, '-_', '+/') ||
      repeat('=', (4 - length(b64url) % 4) % 4) AS b64
    FROM payload
  ),
  decoded AS (
    SELECT convert_from(decode(b64, 'base64'), 'utf8')::jsonb AS payload_json
    FROM normalized
  )
  SELECT payload_json ->> 'ref'
  FROM decoded
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_supabase_functions_base_url()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 'https://' || ref || '.supabase.co/functions/v1'
  FROM (
    SELECT public.get_supabase_ref_from_service_role() AS ref
  ) t
  WHERE ref IS NOT NULL
    AND ref <> '';
$$;

CREATE OR REPLACE FUNCTION public.cron_fire_journal_consolidate_top_backlog()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_project_id uuid;
  v_url text;
  v_edge_secret text;
  v_request_id bigint;
BEGIN
  SELECT jc.project_id
  INTO v_project_id
  FROM public.journal_claims jc
  WHERE jc.active = true
    AND jc.relationship = 'new'
  GROUP BY jc.project_id
  ORDER BY count(*) DESC, min(jc.created_at) ASC
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_url := public.get_supabase_functions_base_url() || '/journal-consolidate';
  v_edge_secret := public.get_pipeline_credential('EDGE_SHARED_SECRET');

  IF v_url IS NULL OR v_edge_secret IS NULL OR v_edge_secret = '' THEN
    RAISE EXCEPTION 'Missing cron prerequisites: v_url=% v_edge_secret_set=%',
      v_url,
      (v_edge_secret IS NOT NULL AND v_edge_secret <> '');
  END IF;

  SELECT net.http_post(
    url := v_url,
    body := jsonb_build_object('project_id', v_project_id),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Edge-Secret', v_edge_secret,
      'X-Source', 'pg_cron:journal-consolidate-top-backlog'
    ),
    timeout_milliseconds := 60000
  )
  INTO v_request_id;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_fire_morning_digest()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text;
  v_edge_secret text;
  v_request_id bigint;
BEGIN
  v_url := public.get_supabase_functions_base_url() || '/morning-digest';
  v_edge_secret := public.get_pipeline_credential('EDGE_SHARED_SECRET');

  IF v_url IS NULL OR v_edge_secret IS NULL OR v_edge_secret = '' THEN
    RAISE EXCEPTION 'Missing cron prerequisites: v_url=% v_edge_secret_set=%',
      v_url,
      (v_edge_secret IS NOT NULL AND v_edge_secret <> '');
  END IF;

  SELECT net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Edge-Secret', v_edge_secret,
      'X-Source', 'pg_cron:morning-digest'
    ),
    timeout_milliseconds := 60000
  )
  INTO v_request_id;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_fire_auto_review_resolver()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url text;
  v_edge_secret text;
  v_request_id bigint;
BEGIN
  v_url := public.get_supabase_functions_base_url() || '/auto-review-resolver';
  v_edge_secret := public.get_pipeline_credential('EDGE_SHARED_SECRET');

  IF v_url IS NULL OR v_edge_secret IS NULL OR v_edge_secret = '' THEN
    RAISE EXCEPTION 'Missing cron prerequisites: v_url=% v_edge_secret_set=%',
      v_url,
      (v_edge_secret IS NOT NULL AND v_edge_secret <> '');
  END IF;

  SELECT net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'dry_run', false,
      'limit', 500,
      'high_confidence_threshold', 0.85,
      'low_confidence_threshold', 0.20,
      'actor', 'system:auto_review_resolver_cron'
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Edge-Secret', v_edge_secret,
      'X-Source', 'pg_cron:auto-review-resolver'
    ),
    timeout_milliseconds := 60000
  )
  INTO v_request_id;

  RETURN v_request_id;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto_review_resolver_daily') THEN
        PERFORM cron.unschedule((SELECT jobid FROM cron.job WHERE jobname = 'auto_review_resolver_daily'));
      END IF;

      PERFORM cron.schedule(
        'auto_review_resolver_daily',
        '15 13 * * *',
        'SELECT public.cron_fire_auto_review_resolver();'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'auto-review-resolver cron registration skipped: %', SQLERRM;
    END;

    BEGIN
      IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'journal-consolidate-top-backlog-15m') THEN
        PERFORM cron.unschedule((SELECT jobid FROM cron.job WHERE jobname = 'journal-consolidate-top-backlog-15m'));
      END IF;

      PERFORM cron.schedule(
        'journal-consolidate-top-backlog-15m',
        '*/15 * * * *',
        'SELECT public.cron_fire_journal_consolidate_top_backlog();'
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'journal-consolidate cron registration skipped: %', SQLERRM;
    END;

    BEGIN
      IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'morning_digest_daily') THEN
        PERFORM cron.schedule(
          'morning_digest_daily',
          '20 13 * * *',
          'SELECT public.cron_fire_morning_digest();'
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'morning-digest cron registration skipped: %', SQLERRM;
    END;
  END IF;
END;
$$;
