-- Phase 1 Gate Metrics Views
-- No JSON parsing - all from first-class columns

-- View: Attribution confidence distribution
CREATE OR REPLACE VIEW v_metrics_attribution_confidence AS
WITH bucketed AS (
  SELECT
    CASE 
      WHEN project_attribution_confidence IS NULL THEN 'unprocessed'
      WHEN project_attribution_confidence >= 0.8 THEN 'high'
      WHEN project_attribution_confidence >= 0.5 THEN 'medium'
      ELSE 'low'
    END as confidence_band,
    CASE 
      WHEN project_attribution_confidence IS NULL THEN 4
      WHEN project_attribution_confidence >= 0.8 THEN 1
      WHEN project_attribution_confidence >= 0.5 THEN 2
      ELSE 3
    END as sort_order
  FROM interactions
)
SELECT
  confidence_band,
  count(*) as interaction_count,
  round(100.0 * count(*) / sum(count(*)) OVER (), 2) as pct
FROM bucketed
GROUP BY confidence_band, sort_order
ORDER BY sort_order;

-- View: Needs review rate
CREATE OR REPLACE VIEW v_metrics_needs_review AS
SELECT
  COALESCE(needs_review, false) as needs_review,
  count(*) as interaction_count,
  round(100.0 * count(*) / sum(count(*)) OVER (), 2) as pct
FROM interactions
GROUP BY 1;

-- View: Scheduler items attribution status distribution
CREATE OR REPLACE VIEW v_metrics_scheduler_attribution AS
SELECT
  COALESCE(attribution_status, 'unknown') as attribution_status,
  count(*) as item_count,
  round(100.0 * count(*) / sum(count(*)) OVER (), 2) as pct
FROM scheduler_items
GROUP BY 1
ORDER BY item_count DESC;

-- View: Project coverage by contact (for candidate set quality)
CREATE OR REPLACE VIEW v_metrics_candidate_coverage AS
SELECT
  c.id as contact_id,
  c.name as contact_name,
  c.trade,
  count(distinct pc.project_id) as assigned_projects,
  count(distinct cpa.project_id) as affinity_projects,
  count(distinct i.id) as total_interactions
FROM contacts c
LEFT JOIN project_contacts pc ON pc.contact_id = c.id AND pc.is_active = true
LEFT JOIN correspondent_project_affinity cpa ON cpa.contact_id = c.id AND cpa.weight > 0.1
LEFT JOIN interactions i ON i.contact_phone = c.phone OR i.contact_phone = c.secondary_phone
WHERE c.contact_type IN ('vendor', 'subcontractor', 'site_supervisor')
GROUP BY 1, 2, 3
HAVING count(distinct i.id) >= 1
ORDER BY total_interactions DESC;

-- View: Override rate by contact (learning loop health)
CREATE OR REPLACE VIEW v_metrics_override_rate AS
SELECT
  c.id as contact_id,
  c.name as contact_name,
  c.trade,
  sum(cpa.confirmation_count) as total_confirmations,
  sum(cpa.rejection_count) as total_rejections,
  CASE 
    WHEN sum(COALESCE(cpa.confirmation_count, 0)) + sum(COALESCE(cpa.rejection_count, 0)) = 0 THEN null
    ELSE round(100.0 * sum(COALESCE(cpa.rejection_count, 0)) / (sum(COALESCE(cpa.confirmation_count, 0)) + sum(COALESCE(cpa.rejection_count, 0))), 2)
  END as rejection_rate_pct
FROM contacts c
JOIN correspondent_project_affinity cpa ON cpa.contact_id = c.id
GROUP BY 1, 2, 3
ORDER BY (sum(COALESCE(cpa.confirmation_count, 0)) + sum(COALESCE(cpa.rejection_count, 0))) DESC NULLS LAST;

-- View: Summary dashboard (single-query health check)
CREATE OR REPLACE VIEW v_metrics_phase1_summary AS
SELECT
  (SELECT count(*) FROM interactions WHERE project_id IS NOT NULL) as interactions_attributed,
  (SELECT count(*) FROM interactions) as interactions_total,
  (SELECT count(*) FROM interactions WHERE needs_review = true) as interactions_needs_review,
  (SELECT count(*) FROM scheduler_items WHERE attribution_status = 'resolved') as items_resolved,
  (SELECT count(*) FROM scheduler_items WHERE attribution_status = 'needs_clarification') as items_needs_clarification,
  (SELECT count(*) FROM scheduler_items) as items_total,
  (SELECT count(*) FROM project_contacts WHERE is_active = true) as active_assignments,
  (SELECT count(*) FROM correspondent_project_affinity WHERE weight > 0.1) as affinity_edges,
  (SELECT sum(confirmation_count) FROM correspondent_project_affinity) as total_confirmations,
  (SELECT sum(rejection_count) FROM correspondent_project_affinity) as total_rejections;

COMMENT ON VIEW v_metrics_attribution_confidence IS 'Phase 1 gate: Attribution confidence distribution (high/medium/low)';
COMMENT ON VIEW v_metrics_needs_review IS 'Phase 1 gate: Needs review rate';
COMMENT ON VIEW v_metrics_scheduler_attribution IS 'Phase 1 gate: Resolved/unknown/needs_clarification distribution';
COMMENT ON VIEW v_metrics_candidate_coverage IS 'Phase 1 gate: Candidate set quality per contact';
COMMENT ON VIEW v_metrics_override_rate IS 'Phase 1 gate: Learning loop health - override/rejection rates';
COMMENT ON VIEW v_metrics_phase1_summary IS 'Single-query health check for all Phase 1 metrics';;
