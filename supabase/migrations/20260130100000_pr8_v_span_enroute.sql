-- PR-8: v_span_enroute view for "enroute-to-what" ops query
-- Shows spans with detected place mentions and their roles
--
-- Use case: Debug enroute detection, verify verb-driven role tagging
-- DATA can query this view to see mentions_24h, pending review count, samples

BEGIN;

-- ============================================================
-- 1. v_span_enroute: Enroute detection ops view
-- ============================================================
CREATE OR REPLACE VIEW v_span_enroute AS
SELECT
  spm.id AS mention_id,
  spm.span_id,
  cs.interaction_id,
  spm.place_name,
  spm.role,
  spm.trigger_verb,
  spm.snippet,
  spm.lat,
  spm.lon,
  gp.state AS place_state,
  spm.created_at AS mention_created_at,
  cs.created_at AS span_created_at,
  -- Join to see if span is in review queue
  CASE WHEN rq.id IS NOT NULL AND rq.resolved_at IS NULL THEN true ELSE false END AS pending_review,
  -- Attribution status
  sa.applied_project_id,
  sa.attribution_lock,
  p.name AS applied_project_name
FROM span_place_mentions spm
JOIN conversation_spans cs ON cs.id = spm.span_id
LEFT JOIN geo_places gp ON gp.id = spm.geo_place_id
LEFT JOIN review_queue rq ON rq.span_id = spm.span_id
LEFT JOIN span_attributions sa ON sa.span_id = spm.span_id
LEFT JOIN projects p ON p.id = sa.applied_project_id
ORDER BY spm.created_at DESC;

COMMENT ON VIEW v_span_enroute IS
  'Ops view for enroute detection debugging. Shows place mentions with roles, review status, and attribution.';

-- ============================================================
-- 2. haversine_miles function (utility for distance queries)
-- ============================================================
CREATE OR REPLACE FUNCTION haversine_miles(
  lat1 DOUBLE PRECISION,
  lon1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lon2 DOUBLE PRECISION
) RETURNS DOUBLE PRECISION AS $$
DECLARE
  R CONSTANT DOUBLE PRECISION := 3959; -- Earth radius in miles
  dlat DOUBLE PRECISION;
  dlon DOUBLE PRECISION;
  a DOUBLE PRECISION;
  c DOUBLE PRECISION;
BEGIN
  dlat := RADIANS(lat2 - lat1);
  dlon := RADIANS(lon2 - lon1);
  a := SIN(dlat / 2) ^ 2 + COS(RADIANS(lat1)) * COS(RADIANS(lat2)) * SIN(dlon / 2) ^ 2;
  c := 2 * ATAN2(SQRT(a), SQRT(1 - a));
  RETURN R * c;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION haversine_miles IS
  'Calculate great-circle distance in miles between two lat/lon points.';

COMMIT;
