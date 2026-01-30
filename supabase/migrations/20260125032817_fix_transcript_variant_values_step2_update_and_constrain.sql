-- Step 2: Update any remaining old values
UPDATE transcripts_comparison 
SET transcript_variant = 'keywords_off' 
WHERE transcript_variant = 'pre';

UPDATE transcripts_comparison 
SET transcript_variant = 'keywords_on' 
WHERE transcript_variant = 'post';

-- Step 3: Add new check constraint
ALTER TABLE transcripts_comparison 
ADD CONSTRAINT transcripts_comparison_transcript_variant_check 
CHECK (transcript_variant = ANY (ARRAY['keywords_off'::text, 'keywords_on'::text]));

-- Add column comment
COMMENT ON COLUMN transcripts_comparison.transcript_variant IS 
'keywords_off = no vocab boost (baseline), keywords_on = vocab boost enabled (GATE 4 comparison)';;
