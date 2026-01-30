-- ============================================================
-- VIEW: Projects with Construction Phase Details
-- ============================================================

CREATE OR REPLACE VIEW v_projects_with_phase AS
SELECT 
  p.id,
  p.name,
  p.job_type,
  p.status AS project_status,
  p.phase AS legacy_phase,  -- the old status field
  
  -- Current construction phase
  cp.code AS phase_code,
  cp.short_name AS phase_short,
  cp.name AS phase_name,
  cp.milestone_name AS next_milestone,
  cp.sequence AS phase_sequence,
  
  -- Project activity
  (SELECT COUNT(*) FROM interactions i WHERE i.project_id = p.id) AS interaction_count,
  (SELECT COUNT(*) FROM scheduler_items si WHERE si.project_id = p.id) AS scheduler_item_count,
  (SELECT MAX(i.event_at_utc) FROM interactions i WHERE i.project_id = p.id) AS last_interaction
  
FROM projects p
LEFT JOIN construction_phases cp ON p.current_construction_phase_id = cp.id
ORDER BY p.name;

COMMENT ON VIEW v_projects_with_phase IS 'Projects with their current construction phase and activity summary';;
