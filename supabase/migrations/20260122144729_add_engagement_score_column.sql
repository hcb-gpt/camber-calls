
-- 2. Add engagement_score as generated column
ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS engagement_score NUMERIC GENERATED ALWAYS AS (
  (interaction_count * 1.0) + ((total_transcript_chars / 150.0) * 0.5)
) STORED;

COMMENT ON COLUMN contacts.engagement_score IS 'Formula: (interaction_count * 1.0) + (total_transcript_minutes * 0.5) where minutes = chars/150';
;
