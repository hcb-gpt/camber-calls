-- DOMINANT_TOPIC Scoring View
-- ⚠️ DISCLAIMER: This scoring method uses DOMINANT_TOPIC_ONLY logic.
-- It does NOT validate truth extraction accuracy.
-- Per STRAT22 directive: "Attribution is claim-level, not call-level."
-- This view exists for backwards compatibility only.

CREATE OR REPLACE VIEW scoring_dominant_topic AS
WITH predictions AS (
  SELECT 
    i.interaction_id,
    p.name AS predicted_project,
    i.project_id AS predicted_project_id,
    i.project_attribution_confidence,
    i.needs_review
  FROM interactions i
  LEFT JOIN projects p ON i.project_id = p.id
),
ground_truth AS (
  SELECT 
    call_id,
    project_attribution AS gt_project,
    confidence AS gt_confidence,
    labeler,
    batch_id
  FROM ground_truth_labels
  WHERE labeler != 'PIPELINE_PENDING_VERIFICATION'
)
SELECT 
  gt.call_id,
  gt.gt_project,
  gt.gt_confidence,
  pred.predicted_project,
  pred.project_attribution_confidence,
  pred.needs_review,
  CASE 
    WHEN gt.gt_project = pred.predicted_project THEN 1 
    WHEN gt.gt_project IS NULL OR pred.predicted_project IS NULL THEN NULL
    ELSE 0 
  END AS correct,
  gt.batch_id,
  gt.labeler,
  '⚠️ DOMINANT_TOPIC_ONLY: Does not validate truth extraction' AS disclaimer
FROM ground_truth gt
LEFT JOIN predictions pred ON gt.call_id = pred.interaction_id;

COMMENT ON VIEW scoring_dominant_topic IS 
'⚠️ DOMINANT_TOPIC_ONLY scoring. Does NOT validate truth extraction accuracy.
Uses call-level project attribution which is a DEFECT per STRAT22 directive.
Exists for backwards compatibility. Use segment-level scoring for accuracy.';;
