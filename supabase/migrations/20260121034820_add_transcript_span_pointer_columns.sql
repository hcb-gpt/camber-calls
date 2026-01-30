-- Add transcript span pointer columns to journal_claims
-- These are v1 pointers: character-based spans in transcript text

-- Pointer type enum
CREATE TYPE pointer_type_enum AS ENUM (
  'transcript_span',  -- v1: char_start/char_end validated
  'audio_span',       -- v2 future: start_sec/end_sec from alignment
  'pointer_invalid',  -- hallucinated or unverifiable
  'pointer_missing'   -- no pointer provided
);

-- Add columns
ALTER TABLE journal_claims
ADD COLUMN char_start INTEGER,
ADD COLUMN char_end INTEGER,
ADD COLUMN span_text TEXT,
ADD COLUMN span_hash TEXT,
ADD COLUMN pointer_type pointer_type_enum DEFAULT 'pointer_missing';

-- Index for pointer validation queries
CREATE INDEX idx_journal_claims_pointer_type ON journal_claims(pointer_type);

COMMENT ON COLUMN journal_claims.char_start IS 'Start character position in transcript (0-indexed)';
COMMENT ON COLUMN journal_claims.char_end IS 'End character position in transcript (0-indexed, exclusive)';
COMMENT ON COLUMN journal_claims.span_text IS 'Extracted substring from transcript for verification';
COMMENT ON COLUMN journal_claims.span_hash IS 'MD5 hash of span_text for integrity check';
COMMENT ON COLUMN journal_claims.pointer_type IS 'v1=transcript_span (promotable), audio_span (future), pointer_invalid (review), pointer_missing (review)';;
