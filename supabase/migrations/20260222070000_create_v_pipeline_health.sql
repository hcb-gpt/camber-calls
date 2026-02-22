CREATE OR REPLACE FUNCTION public.table_health_metric(
  p_table_name text,
  p_ts_col text
)
RETURNS TABLE(total bigint, last_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF to_regclass('public.' || p_table_name) IS NULL THEN
    RETURN QUERY SELECT 0::bigint, NULL::timestamptz;
    RETURN;
  END IF;

  RETURN QUERY EXECUTE format(
    'SELECT count(*)::bigint, max(%I)::timestamptz FROM public.%I',
    p_ts_col,
    p_table_name
  );
END;
$$;

CREATE OR REPLACE VIEW public.v_pipeline_health AS
SELECT
  'calls_raw'::text AS capability,
  m.total,
  m.last_at
FROM public.table_health_metric('calls_raw', 'ingested_at_utc') m

UNION ALL
SELECT
  'transcriptions'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('call_transcriptions', 'created_at') m

UNION ALL
SELECT
  'segments'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('call_segments', 'created_at') m

UNION ALL
SELECT
  'attributions'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('call_attributions', 'created_at') m

UNION ALL
SELECT
  'journal_claims'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('journal_claims', 'created_at') m

UNION ALL
SELECT
  'striking_signals'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('striking_signals', 'created_at') m

UNION ALL
SELECT
  'open_loops'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('journal_open_loops', 'created_at') m

UNION ALL
SELECT
  'summaries'::text,
  m.total,
  m.last_at
FROM public.table_health_metric('call_summaries', 'created_at') m;
