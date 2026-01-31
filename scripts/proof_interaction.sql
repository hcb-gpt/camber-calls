-- proof_interaction.sql
-- STRAT TURN 68: taskpack=proof_sql_pack (GPT-DEV-2)
--
-- Canonical "scoreboard query" for pipeline proof
-- Usage: Replace __INTERACTION_ID__ with actual interaction_id
--
-- Output: Single row with all proof metrics
--   generation | spans_total | spans_active | attributions | review_queue_pending
--   | needs_review_flagged | review_queue_gap | override_reseeds

WITH params AS (
  SELECT '__INTERACTION_ID__'::text AS interaction_id
),

-- All spans for this interaction
all_spans AS (
  SELECT
    cs.id AS span_id,
    cs.segment_generation,
    cs.is_superseded,
    cs.span_index
  FROM conversation_spans cs, params p
  WHERE cs.interaction_id = p.interaction_id
),

-- Span counts by generation
span_stats AS (
  SELECT
    COALESCE(MAX(segment_generation), 0) AS latest_generation,
    COUNT(*) AS spans_total,
    COUNT(*) FILTER (WHERE is_superseded = false) AS spans_active
  FROM all_spans
),

-- Active span IDs (for joins)
active_spans AS (
  SELECT span_id
  FROM all_spans
  WHERE is_superseded = false
),

-- Attributions for active spans
attribution_stats AS (
  SELECT
    COUNT(*) AS attributions,
    COUNT(*) FILTER (WHERE sa.needs_review = true) AS needs_review_flagged
  FROM span_attributions sa
  WHERE sa.span_id IN (SELECT span_id FROM active_spans)
),

-- Review queue for active spans
review_stats AS (
  SELECT
    COUNT(*) AS review_queue_pending
  FROM review_queue rq
  WHERE rq.span_id IN (SELECT span_id FROM active_spans)
    AND rq.status = 'pending'
),

-- Gap detector: needs_review=true but no review_queue entry
gap_detector AS (
  SELECT COUNT(*) AS review_queue_gap
  FROM span_attributions sa
  WHERE sa.span_id IN (SELECT span_id FROM active_spans)
    AND sa.needs_review = true
    AND NOT EXISTS (
      SELECT 1 FROM review_queue rq
      WHERE rq.span_id = sa.span_id
        AND rq.status = 'pending'
    )
),

-- Override log reseed entries
override_stats AS (
  SELECT COUNT(*) AS override_reseeds
  FROM override_log ol, params p
  WHERE ol.interaction_id = p.interaction_id
    AND ol.action = 'reseed'
)

-- Final scoreboard
SELECT
  ss.latest_generation AS generation,
  ss.spans_total,
  ss.spans_active,
  COALESCE(ats.attributions, 0) AS attributions,
  COALESCE(rs.review_queue_pending, 0) AS review_queue_pending,
  COALESCE(ats.needs_review_flagged, 0) AS needs_review_flagged,
  COALESCE(gd.review_queue_gap, 0) AS review_queue_gap,
  COALESCE(os.override_reseeds, 0) AS override_reseeds,
  -- PASS/FAIL conditions
  CASE
    WHEN ss.spans_active < 1 THEN 'FAIL: no active spans'
    WHEN COALESCE(ats.attributions, 0) < 1 THEN 'FAIL: no attributions'
    WHEN COALESCE(gd.review_queue_gap, 0) > 0 THEN 'FAIL: review_queue gap'
    ELSE 'PASS'
  END AS status
FROM span_stats ss
CROSS JOIN attribution_stats ats
CROSS JOIN review_stats rs
CROSS JOIN gap_detector gd
CROSS JOIN override_stats os;
