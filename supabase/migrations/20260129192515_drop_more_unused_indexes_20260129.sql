-- Drop clearly unused indexes on various tables
-- (all flagged by Supabase advisor as never used)

-- ground_truth_segments indexes (table is empty)
DROP INDEX IF EXISTS idx_gt_segments_batch_id;
DROP INDEX IF EXISTS idx_gt_segments_call_id;
DROP INDEX IF EXISTS idx_gt_segments_project_id;
DROP INDEX IF EXISTS idx_gt_segments_turn_type;

-- ground_truth_labels (119 rows but indexes never queried)
DROP INDEX IF EXISTS idx_ground_truth_labels_confidence;

-- local_monikers indexes (never used)
DROP INDEX IF EXISTS idx_local_monikers_normalized;
DROP INDEX IF EXISTS idx_local_monikers_type;
DROP INDEX IF EXISTS idx_local_monikers_project;

-- entity_drift_metrics indexes (never used)
DROP INDEX IF EXISTS idx_drift_metrics_field;
DROP INDEX IF EXISTS idx_drift_metrics_status;;
