-- Function to extract speaker names from transcript
-- Transcripts have format: "Speaker Name: text\nSpeaker Name: text"
CREATE OR REPLACE FUNCTION extract_speakers_from_transcript(transcript_text TEXT)
RETURNS TABLE(
  speaker_name TEXT,
  line_count INT
) AS $$
BEGIN
  RETURN QUERY
  WITH speaker_lines AS (
    SELECT 
      TRIM(REGEXP_REPLACE(
        (REGEXP_MATCHES(line, '^([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)?)\s*:', 'g'))[1],
        '\s+', ' ', 'g'
      )) as speaker
    FROM UNNEST(STRING_TO_ARRAY(transcript_text, E'\n')) as line
    WHERE line ~ '^[A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)?\s*:'
  )
  SELECT 
    speaker as speaker_name,
    COUNT(*)::INT as line_count
  FROM speaker_lines
  WHERE speaker IS NOT NULL AND speaker != ''
  GROUP BY speaker
  ORDER BY line_count DESC;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION extract_speakers_from_transcript IS 
'Extracts speaker names from transcript text. Returns each unique speaker and their line count.';;
