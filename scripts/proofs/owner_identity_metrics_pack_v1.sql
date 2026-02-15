WITH /* owner_identity_metrics_pack_v1: overall (latest calls_raw row per interaction_id) */ latest AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.channel,
    cr.direction,
    cr.owner_phone,
    cr.owner_name,
    cr.other_party_phone,
    cr.other_party_name,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.capture_source,
    cr.is_shadow,
    cr.test_batch
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
)
SELECT
  now() AS measured_at_utc,
  COUNT(*) FILTER (WHERE channel = 'call') AS calls_total,
  COUNT(*) FILTER (WHERE channel = 'call' AND (direction IS NULL OR btrim(direction) = '')) AS direction_missing,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_phone IS NULL OR btrim(owner_phone) = '')) AS owner_phone_missing,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_name IS NULL OR btrim(owner_name) = '')) AS owner_name_missing,
  COUNT(*) FILTER (WHERE channel = 'call' AND (other_party_phone IS NULL OR btrim(other_party_phone) = '')) AS other_party_phone_missing,
  COUNT(*) FILTER (WHERE channel = 'call' AND (other_party_name IS NULL OR btrim(other_party_name) = '')) AS other_party_name_missing,
  COUNT(*) FILTER (WHERE channel = 'call' AND is_shadow IS TRUE) AS shadow_calls,
  COUNT(*) FILTER (WHERE channel = 'call' AND test_batch IS NOT NULL) AS test_batch_calls
FROM latest;

WITH /* owner_identity_metrics_pack_v1: last 30d summary */ latest AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.channel,
    cr.direction,
    cr.owner_phone,
    cr.owner_name,
    cr.other_party_phone,
    cr.other_party_name,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.capture_source,
    cr.is_shadow,
    cr.test_batch
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
)
SELECT
  now() AS measured_at_utc,
  COUNT(*) FILTER (WHERE channel = 'call') AS calls_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (direction IS NULL OR btrim(direction) = '')) AS direction_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_phone IS NULL OR btrim(owner_phone) = '')) AS owner_phone_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_name IS NULL OR btrim(owner_name) = '')) AS owner_name_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (other_party_phone IS NULL OR btrim(other_party_phone) = '')) AS other_party_phone_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (other_party_name IS NULL OR btrim(other_party_name) = '')) AS other_party_name_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND is_shadow IS TRUE) AS shadow_calls_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND test_batch IS NOT NULL) AS test_batch_calls_last_30d
FROM latest
WHERE event_at_utc >= now() - interval '30 days';

WITH /* owner_identity_metrics_pack_v1: last 30d by normalized direction */ latest AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.channel,
    cr.direction,
    cr.owner_phone,
    cr.owner_name,
    cr.other_party_phone,
    cr.other_party_name,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.capture_source,
    cr.is_shadow,
    cr.test_batch
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
norm AS (
  SELECT
    *,
    CASE
      WHEN direction ~* '^(in|inbound|incoming)$' THEN 'inbound'
      WHEN direction ~* '^(out|outbound|outgoing)$' THEN 'outbound'
      ELSE 'unknown'
    END AS direction_norm
  FROM latest
)
SELECT
  direction_norm,
  COUNT(*) FILTER (WHERE channel = 'call') AS calls_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_phone IS NULL OR btrim(owner_phone) = '')) AS owner_phone_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_name IS NULL OR btrim(owner_name) = '')) AS owner_name_missing_last_30d
FROM norm
WHERE event_at_utc >= now() - interval '30 days'
GROUP BY 1
ORDER BY 2 DESC;

WITH /* owner_identity_metrics_pack_v1: last 30d by pipeline_version */ latest AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.channel,
    cr.direction,
    cr.owner_phone,
    cr.owner_name,
    cr.other_party_phone,
    cr.other_party_name,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.capture_source,
    cr.is_shadow,
    cr.test_batch
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
)
SELECT
  pipeline_version,
  COUNT(*) FILTER (WHERE channel = 'call') AS calls_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_phone IS NULL OR btrim(owner_phone) = '')) AS owner_phone_missing_last_30d,
  COUNT(*) FILTER (WHERE channel = 'call' AND (owner_name IS NULL OR btrim(owner_name) = '')) AS owner_name_missing_last_30d
FROM latest
WHERE event_at_utc >= now() - interval '30 days'
GROUP BY 1
ORDER BY 2 DESC, 1 ASC;

