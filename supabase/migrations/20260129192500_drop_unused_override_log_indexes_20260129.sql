-- Drop unused indexes on override_log (7 unused indexes reported)
DROP INDEX IF EXISTS idx_override_log_entity_type;
DROP INDEX IF EXISTS idx_override_log_entity_id;
DROP INDEX IF EXISTS idx_override_log_field;
DROP INDEX IF EXISTS override_log_entity_key_idx;;
