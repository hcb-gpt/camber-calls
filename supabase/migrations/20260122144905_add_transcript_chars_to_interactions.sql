-- Add transcript_chars column to interactions for tracking depth
ALTER TABLE interactions ADD COLUMN IF NOT EXISTS transcript_chars integer DEFAULT 0;

-- Backfill from calls_raw
UPDATE interactions i
SET transcript_chars = LENGTH(cr.transcript)
FROM calls_raw cr
WHERE cr.interaction_id = i.interaction_id
  AND cr.transcript IS NOT NULL;;
