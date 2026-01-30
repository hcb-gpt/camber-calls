ALTER TABLE transcripts_comparison 
ADD COLUMN words JSONB;

COMMENT ON COLUMN transcripts_comparison.words IS 
'Word-level timestamps from Deepgram: [{word, start, end, speaker, confidence}]';;
