-- Drop duplicate indexes (keeping shorter-named versions)
DROP INDEX IF EXISTS idx_override_log_created_at;
DROP INDEX IF EXISTS idx_review_queue_created_at;
DROP INDEX IF EXISTS idx_review_queue_interaction_id;;
