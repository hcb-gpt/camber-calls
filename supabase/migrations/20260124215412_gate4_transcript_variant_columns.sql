
-- GATE 4: PRE/POST Toggle Schema Support
ALTER TABLE transcripts_comparison
ADD COLUMN IF NOT EXISTS transcript_variant TEXT CHECK (transcript_variant IN ('pre', 'post')),
ADD COLUMN IF NOT EXISTS keywords_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS vocab_terms_count INTEGER,
ADD COLUMN IF NOT EXISTS vocab_query_ms INTEGER;

COMMENT ON COLUMN transcripts_comparison.transcript_variant IS 'pre = no keywords, post = keywords injected';
COMMENT ON COLUMN transcripts_comparison.keywords_enabled IS 'Whether dynamic vocab was enabled for this transcription';
;
