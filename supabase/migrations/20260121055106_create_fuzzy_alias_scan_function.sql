-- Function to scan transcript text for fuzzy alias matches
-- Returns all projects that match any term in the transcript
CREATE OR REPLACE FUNCTION scan_transcript_for_projects(
  transcript_text TEXT,
  similarity_threshold FLOAT DEFAULT 0.35,
  min_word_length INT DEFAULT 4
)
RETURNS TABLE(
  project_id UUID,
  project_name TEXT,
  matched_term TEXT,
  matched_alias TEXT,
  match_type TEXT,
  score FLOAT
) AS $$
DECLARE
  v_word TEXT;
  v_words TEXT[];
BEGIN
  -- Extract words from transcript (lowercase, alpha only, min length)
  SELECT ARRAY_AGG(DISTINCT w) INTO v_words
  FROM (
    SELECT LOWER(REGEXP_REPLACE(word, '[^a-zA-Z]', '', 'g')) as w
    FROM UNNEST(STRING_TO_ARRAY(transcript_text, ' ')) as word
    WHERE LENGTH(REGEXP_REPLACE(word, '[^a-zA-Z]', '', 'g')) >= min_word_length
  ) t
  WHERE w != '';

  -- For each word, find fuzzy matches
  RETURN QUERY
  SELECT DISTINCT ON (fm.project_id, v.word)
    fm.project_id,
    fm.project_name,
    v.word as matched_term,
    fm.alias as matched_alias,
    fm.match_type,
    fm.score
  FROM UNNEST(v_words) as v(word)
  CROSS JOIN LATERAL find_fuzzy_alias_matches(v.word, similarity_threshold) fm
  WHERE fm.score >= similarity_threshold
  ORDER BY fm.project_id, v.word, fm.score DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION scan_transcript_for_projects IS 
'Scans transcript text for words that fuzzy-match project aliases. Returns candidate projects with match details.';;
