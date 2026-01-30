
-- Add tiered confidence thresholds per Strat guidance
INSERT INTO inference_config (config_key, config_value, description, updated_by)
VALUES 
  ('proposal_auto_assign_threshold', '0.70', 'Confidence >= this for auto-assign on proposals/promises (squishy OK)', 'Strat'),
  ('scheduler_auto_assign_threshold', '0.85', 'Confidence >= this for auto-assign on calendar/scheduler items', 'Strat'),
  ('finance_auto_assign_threshold', '0.95', 'Confidence >= this for auto-assign on financial/cost code inference', 'Strat'),
  ('project_id_required_threshold', '0.95', 'Project identification confidence required before finance auto-assign', 'Strat')
ON CONFLICT (config_key) DO UPDATE SET
  config_value = EXCLUDED.config_value,
  description = EXCLUDED.description,
  updated_by = EXCLUDED.updated_by,
  updated_at = NOW();
;
