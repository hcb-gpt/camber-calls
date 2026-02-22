-- sms_ingestion_path_health.sql
-- Read-only probe for SMS ingestion bridge health.
-- Verifies whether SMS records progress from sms_messages -> calls_raw -> interactions.

WITH latest AS (
  SELECT
    (SELECT max(ingested_at) FROM public.sms_messages) AS sms_latest_ingested_at,
    (SELECT max(ingested_at_utc) FROM public.calls_raw WHERE channel = 'sms') AS calls_raw_sms_latest_ingested_at,
    (SELECT max(ingested_at_utc) FROM public.interactions WHERE channel = 'sms') AS interactions_sms_latest_ingested_at
),
counts AS (
  SELECT 'sms_messages_24h' AS metric, count(*)::bigint AS n
  FROM public.sms_messages
  WHERE ingested_at >= now() - interval '24 hours'
  UNION ALL
  SELECT 'calls_raw_sms_24h', count(*)::bigint
  FROM public.calls_raw
  WHERE channel = 'sms'
    AND ingested_at_utc >= now() - interval '24 hours'
  UNION ALL
  SELECT 'interactions_sms_24h', count(*)::bigint
  FROM public.interactions
  WHERE channel = 'sms'
    AND ingested_at_utc >= now() - interval '24 hours'
  UNION ALL
  SELECT 'sms_messages_7d', count(*)::bigint
  FROM public.sms_messages
  WHERE ingested_at >= now() - interval '7 days'
  UNION ALL
  SELECT 'calls_raw_sms_7d', count(*)::bigint
  FROM public.calls_raw
  WHERE channel = 'sms'
    AND ingested_at_utc >= now() - interval '7 days'
  UNION ALL
  SELECT 'interactions_sms_7d', count(*)::bigint
  FROM public.interactions
  WHERE channel = 'sms'
    AND ingested_at_utc >= now() - interval '7 days'
),
schema_bridge_checks AS (
  SELECT
    (SELECT count(*)::bigint
     FROM pg_trigger t
     JOIN pg_class c ON c.oid = t.tgrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'sms_messages'
       AND NOT t.tgisinternal) AS sms_trigger_count,
    (SELECT count(*)::bigint
     FROM information_schema.routines r
     WHERE r.routine_schema = 'public'
       AND r.routine_definition ILIKE '%sms_messages%') AS routine_refs_sms_messages
)
SELECT metric, n, NULL::timestamptz AS ts, NULL::bigint AS n2
FROM counts
UNION ALL
SELECT 'sms_messages_latest' AS metric, NULL::bigint AS n, sms_latest_ingested_at AS ts, NULL::bigint AS n2
FROM latest
UNION ALL
SELECT 'calls_raw_sms_latest', NULL::bigint, calls_raw_sms_latest_ingested_at, NULL::bigint
FROM latest
UNION ALL
SELECT 'interactions_sms_latest', NULL::bigint, interactions_sms_latest_ingested_at, NULL::bigint
FROM latest
UNION ALL
SELECT 'sms_messages_trigger_count', sms_trigger_count, NULL::timestamptz, NULL::bigint
FROM schema_bridge_checks
UNION ALL
SELECT 'routine_refs_sms_messages', routine_refs_sms_messages, NULL::timestamptz, NULL::bigint
FROM schema_bridge_checks
ORDER BY metric;
