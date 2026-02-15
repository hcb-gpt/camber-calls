WITH latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.direction,
    cr.is_shadow,
    cr.test_batch,
    cr.raw_snapshot_json
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
latest_interaction AS (
  SELECT DISTINCT ON (i.interaction_id)
    i.interaction_id,
    i.event_at_utc,
    i.contact_id,
    i.project_id,
    i.needs_review,
    i.review_reasons,
    i.project_attribution_confidence,
    i.is_shadow
  FROM public.interactions i
  ORDER BY
    i.interaction_id,
    i.event_at_utc DESC NULLS LAST,
    i.ingested_at_utc DESC NULLS LAST,
    i.id DESC
),
pending_null_span AS (
  SELECT *
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
    AND rq.span_id IS NULL
),
enriched AS (
  SELECT
    rq.id,
    rq.interaction_id,
    rq.module,
    rq.reason_codes,
    rq.reasons,
    rq.created_at,
    rq.updated_at,
    lc.event_at_utc AS call_event_at_utc,
    lc.pipeline_version,
    lc.direction,
    lc.is_shadow AS call_is_shadow,
    lc.test_batch AS call_test_batch,
    (lc.raw_snapshot_json->'signal'->'raw_event'->>'test_batch') AS signal_test_batch,
    li.contact_id,
    li.project_id,
    li.needs_review,
    li.project_attribution_confidence
  FROM pending_null_span rq
  LEFT JOIN latest_call lc ON lc.call_id = rq.interaction_id
  LEFT JOIN latest_interaction li ON li.interaction_id = rq.interaction_id
)
SELECT
  now() AS measured_at_utc,
  COUNT(*) AS pending_null_span_total,
  COUNT(*) FILTER (WHERE module = 'process_call') AS pending_process_call_null_span,
  COUNT(*) FILTER (WHERE module IS NULL OR btrim(module) = '') AS pending_module_blank_null_span,
  COUNT(*) FILTER (WHERE interaction_id IS NULL OR btrim(interaction_id) = '') AS pending_missing_interaction_id
FROM enriched;

WITH pending_null_span AS (
  SELECT *
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
    AND rq.span_id IS NULL
),
latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.direction,
    cr.is_shadow,
    cr.test_batch,
    cr.raw_snapshot_json
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
latest_interaction AS (
  SELECT DISTINCT ON (i.interaction_id)
    i.interaction_id,
    i.event_at_utc,
    i.contact_id,
    i.project_id,
    i.needs_review
  FROM public.interactions i
  ORDER BY
    i.interaction_id,
    i.event_at_utc DESC NULLS LAST,
    i.ingested_at_utc DESC NULLS LAST,
    i.id DESC
),
e AS (
  SELECT
    rq.*,
    lc.event_at_utc AS call_event_at_utc,
    lc.pipeline_version,
    lc.direction,
    lc.is_shadow AS call_is_shadow,
    lc.test_batch AS call_test_batch,
    (lc.raw_snapshot_json->'signal'->'raw_event'->>'test_batch') AS signal_test_batch,
    li.contact_id,
    li.project_id,
    li.needs_review,
    CASE
      WHEN
        lc.is_shadow IS TRUE
        OR lc.test_batch IS NOT NULL
        OR (lc.raw_snapshot_json->'signal'->'raw_event'->>'test_batch') IS NOT NULL
        OR rq.interaction_id ~ '^cll_(DEV|AUTH|SUMMTEST|ITEST|SHADOW|TEST)'
        OR rq.interaction_id ~ 'TEST'
      THEN 'synthetic_test'
      WHEN li.interaction_id IS NULL THEN 'missing_interaction_row'
      WHEN li.needs_review IS FALSE OR (li.contact_id IS NOT NULL AND li.project_id IS NOT NULL) THEN 'stale_already_resolved'
      ELSE 'real_pending'
    END AS bucket
  FROM pending_null_span rq
  LEFT JOIN latest_call lc ON lc.call_id = rq.interaction_id
  LEFT JOIN latest_interaction li ON li.interaction_id = rq.interaction_id
)
SELECT
  module,
  bucket,
  COUNT(*) AS row_count,
  COUNT(DISTINCT interaction_id) AS interaction_count
FROM e
GROUP BY 1, 2
ORDER BY row_count DESC, module ASC, bucket ASC;

WITH rq AS (
  SELECT *
  FROM public.review_queue
  WHERE status = 'pending'
    AND span_id IS NULL
    AND module = 'process_call'
),
latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.direction,
    cr.is_shadow,
    cr.test_batch,
    cr.owner_phone,
    cr.other_party_phone
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
latest_interaction AS (
  SELECT DISTINCT ON (i.interaction_id)
    i.interaction_id,
    i.event_at_utc,
    i.contact_id,
    i.project_id,
    i.needs_review
  FROM public.interactions i
  ORDER BY
    i.interaction_id,
    i.event_at_utc DESC NULLS LAST,
    i.ingested_at_utc DESC NULLS LAST,
    i.id DESC
),
e AS (
  SELECT
    rq.*,
    lc.event_at_utc AS call_event_at_utc,
    lc.pipeline_version,
    lc.direction,
    lc.is_shadow AS call_is_shadow,
    lc.test_batch AS call_test_batch,
    lc.owner_phone,
    lc.other_party_phone,
    li.contact_id,
    li.project_id,
    li.needs_review,
    CASE
      WHEN
        lc.is_shadow IS TRUE
        OR lc.test_batch IS NOT NULL
        OR rq.interaction_id ~ '^cll_(DEV|AUTH|SUMMTEST|ITEST|SHADOW|TEST)'
        OR rq.interaction_id ~ 'TEST'
      THEN 'synthetic_test'
      WHEN li.interaction_id IS NULL THEN 'missing_interaction_row'
      WHEN li.needs_review IS FALSE OR (li.contact_id IS NOT NULL AND li.project_id IS NOT NULL) THEN 'stale_already_resolved'
      ELSE 'real_pending'
    END AS bucket
  FROM rq
  LEFT JOIN latest_call lc ON lc.call_id = rq.interaction_id
  LEFT JOIN latest_interaction li ON li.interaction_id = rq.interaction_id
)
SELECT
  pipeline_version,
  bucket,
  COUNT(*) AS row_count,
  COUNT(*) FILTER (WHERE owner_phone IS NULL OR btrim(owner_phone) = '') AS owner_phone_missing,
  COUNT(*) FILTER (WHERE other_party_phone IS NULL OR btrim(other_party_phone) = '') AS other_party_phone_missing
FROM e
GROUP BY 1, 2
ORDER BY row_count DESC, pipeline_version ASC, bucket ASC;

WITH rq AS (
  SELECT *
  FROM public.review_queue
  WHERE status = 'pending'
    AND span_id IS NULL
    AND module = 'process_call'
),
reason_rows AS (
  SELECT
    rc AS reason_code,
    COUNT(*) AS row_count
  FROM rq, unnest(coalesce(rq.reason_codes, rq.reasons)) AS rc
  GROUP BY 1
)
SELECT reason_code, row_count
FROM reason_rows
ORDER BY row_count DESC, reason_code ASC
LIMIT 50;

-- Sample: newest “real_pending” process_call rows (for inspection)
WITH rq AS (
  SELECT *
  FROM public.review_queue
  WHERE status = 'pending'
    AND span_id IS NULL
    AND module = 'process_call'
),
latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.event_at_utc,
    cr.pipeline_version,
    cr.direction,
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
latest_interaction AS (
  SELECT DISTINCT ON (i.interaction_id)
    i.interaction_id,
    i.event_at_utc,
    i.contact_id,
    i.project_id,
    i.needs_review,
    i.project_attribution_confidence
  FROM public.interactions i
  ORDER BY
    i.interaction_id,
    i.event_at_utc DESC NULLS LAST,
    i.ingested_at_utc DESC NULLS LAST,
    i.id DESC
),
e AS (
  SELECT
    rq.id,
    rq.interaction_id,
    rq.created_at,
    rq.updated_at,
    rq.reason_codes,
    lc.event_at_utc AS call_event_at_utc,
    lc.pipeline_version,
    lc.direction,
    lc.is_shadow AS call_is_shadow,
    lc.test_batch AS call_test_batch,
    li.contact_id,
    li.project_id,
    li.needs_review,
    li.project_attribution_confidence,
    CASE
      WHEN
        lc.is_shadow IS TRUE
        OR lc.test_batch IS NOT NULL
        OR rq.interaction_id ~ '^cll_(DEV|AUTH|SUMMTEST|ITEST|SHADOW|TEST)'
        OR rq.interaction_id ~ 'TEST'
      THEN 'synthetic_test'
      WHEN li.interaction_id IS NULL THEN 'missing_interaction_row'
      WHEN li.needs_review IS FALSE OR (li.contact_id IS NOT NULL AND li.project_id IS NOT NULL) THEN 'stale_already_resolved'
      ELSE 'real_pending'
    END AS bucket
  FROM rq
  LEFT JOIN latest_call lc ON lc.call_id = rq.interaction_id
  LEFT JOIN latest_interaction li ON li.interaction_id = rq.interaction_id
)
SELECT
  id,
  interaction_id,
  bucket,
  call_event_at_utc,
  pipeline_version,
  direction,
  project_attribution_confidence,
  reason_codes
FROM e
WHERE bucket = 'real_pending'
ORDER BY call_event_at_utc DESC NULLS LAST, updated_at DESC NULLS LAST
LIMIT 25;
