-- Add lineage columns for capture provenance
ALTER TABLE calls_raw ADD COLUMN IF NOT EXISTS zap_id TEXT;
ALTER TABLE calls_raw ADD COLUMN IF NOT EXISTS zap_step_id TEXT;
ALTER TABLE calls_raw ADD COLUMN IF NOT EXISTS beside_note_url TEXT;

-- Backfill beside_note_url from raw_snapshot_json
UPDATE calls_raw
SET beside_note_url = raw_snapshot_json->'signal'->>'note_url'
WHERE beside_note_url IS NULL
  AND raw_snapshot_json->'signal'->>'note_url' IS NOT NULL;;
