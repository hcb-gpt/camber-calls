-- Step 1: Drop old check constraint first
ALTER TABLE transcripts_comparison 
DROP CONSTRAINT IF EXISTS transcripts_comparison_transcript_variant_check;;
