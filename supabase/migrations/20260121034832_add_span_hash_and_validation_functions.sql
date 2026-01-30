-- Function to compute span_hash from text
CREATE OR REPLACE FUNCTION compute_span_hash(span_text TEXT)
RETURNS TEXT AS $$
BEGIN
  IF span_text IS NULL OR span_text = '' THEN
    RETURN NULL;
  END IF;
  RETURN md5(span_text);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to validate a transcript span
-- Returns true if char_start/char_end extract the expected span_text from transcript
CREATE OR REPLACE FUNCTION validate_transcript_span(
  transcript TEXT,
  p_char_start INTEGER,
  p_char_end INTEGER,
  expected_span_text TEXT
) RETURNS BOOLEAN AS $$
DECLARE
  extracted TEXT;
BEGIN
  IF transcript IS NULL OR p_char_start IS NULL OR p_char_end IS NULL THEN
    RETURN FALSE;
  END IF;
  
  IF p_char_start < 0 OR p_char_end <= p_char_start THEN
    RETURN FALSE;
  END IF;
  
  IF p_char_end > length(transcript) THEN
    RETURN FALSE;
  END IF;
  
  -- Extract substring (PostgreSQL substr is 1-indexed, so add 1)
  extracted := substr(transcript, p_char_start + 1, p_char_end - p_char_start);
  
  -- Compare with expected (case-insensitive, trimmed)
  RETURN lower(trim(extracted)) = lower(trim(COALESCE(expected_span_text, '')));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION compute_span_hash(TEXT) IS 'Computes MD5 hash of span text for pointer integrity verification';
COMMENT ON FUNCTION validate_transcript_span(TEXT, INTEGER, INTEGER, TEXT) IS 'Validates that char_start/char_end extract the expected span_text from transcript';;
