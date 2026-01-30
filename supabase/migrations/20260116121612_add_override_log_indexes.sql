CREATE INDEX IF NOT EXISTS idx_override_log_entity_type ON override_log(entity_type);
CREATE INDEX IF NOT EXISTS idx_override_log_created_at ON override_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_override_log_entity_id ON override_log(entity_id);;
