
-- Canary-B: Allow NULL speaker_entity_id (no entities table exists)
ALTER TABLE belief_claims ALTER COLUMN speaker_entity_id DROP NOT NULL;

COMMENT ON COLUMN belief_claims.speaker_entity_id IS 'Speaker entity UUID. NULLABLE in v1 (no entity resolution yet). Will be populated when speaker resolution is implemented.';
;
