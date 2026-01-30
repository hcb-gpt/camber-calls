-- EVAL1 Scoring Harness
-- Generates EVAL1 report with explicit DOMINANT_TOPIC_ONLY disclaimer

CREATE OR REPLACE FUNCTION generate_eval1_report(
  p_batch_ids TEXT[] DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_report JSONB;
  v_batch_filter TEXT[];
BEGIN
  -- Default to all verified batches
  IF p_batch_ids IS NULL THEN
    v_batch_filter := ARRAY['BATCH1', 'BATCH2', 'BATCH3', 'BATCH4', 'BATCH5'];
  ELSE
    v_batch_filter := p_batch_ids;
  END IF;

  WITH scored AS (
    SELECT 
      s.*,
      CASE 
        WHEN s.gt_confidence = 'HIGH' THEN 3
        WHEN s.gt_confidence = 'MEDIUM' THEN 2
        WHEN s.gt_confidence = 'LOW' THEN 1
        ELSE 0
      END AS confidence_weight
    FROM scoring_dominant_topic s
    WHERE s.batch_id = ANY(v_batch_filter)
  ),
  by_batch AS (
    SELECT 
      batch_id,
      COUNT(*) AS n,
      SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) AS correct,
      ROUND(100.0 * SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS accuracy
    FROM scored
    GROUP BY batch_id
  ),
  overall AS (
    SELECT 
      COUNT(*) AS total_calls,
      SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) AS total_correct,
      SUM(CASE WHEN correct = 0 THEN 1 ELSE 0 END) AS total_incorrect,
      SUM(CASE WHEN correct IS NULL THEN 1 ELSE 0 END) AS total_null,
      ROUND(100.0 * SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS overall_accuracy
    FROM scored
  ),
  by_confidence AS (
    SELECT 
      gt_confidence,
      COUNT(*) AS n,
      SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) AS correct,
      ROUND(100.0 * SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS accuracy
    FROM scored
    WHERE gt_confidence IS NOT NULL
    GROUP BY gt_confidence
  )
  SELECT jsonb_build_object(
    'report_type', 'EVAL1',
    'report_version', '1.0.0',
    'generated_at', now(),
    'disclaimer', '⚠️ DOMINANT_TOPIC_ONLY: This scoring uses call-level project attribution which is a DEFECT per STRAT22 directive. Does NOT validate truth extraction accuracy. Use segment-level scoring for accurate evaluation.',
    'batches_included', v_batch_filter,
    'overall', (SELECT row_to_json(overall) FROM overall),
    'by_batch', (SELECT jsonb_agg(row_to_json(by_batch)) FROM by_batch),
    'by_confidence', (SELECT jsonb_agg(row_to_json(by_confidence)) FROM by_confidence)
  ) INTO v_report;
  
  RETURN v_report;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_eval1_report IS 
'Generates EVAL1 scoring report with DOMINANT_TOPIC_ONLY disclaimer.
Per STRAT22: call-level attribution is a defect. This exists for backwards compatibility only.';;
