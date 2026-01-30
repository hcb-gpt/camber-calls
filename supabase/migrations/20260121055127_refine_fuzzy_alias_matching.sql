-- Refine fuzzy matching to reduce false positives
-- 1. Increase min word length
-- 2. Add stopword filtering
-- 3. Tighten thresholds for phonetic matches

CREATE OR REPLACE FUNCTION scan_transcript_for_projects(
  transcript_text TEXT,
  similarity_threshold FLOAT DEFAULT 0.4,
  min_word_length INT DEFAULT 5
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
  v_stopwords TEXT[] := ARRAY[
    'about', 'after', 'again', 'also', 'another', 'back', 'because', 'been', 
    'before', 'being', 'call', 'called', 'change', 'changed', 'come', 'could', 
    'doing', 'done', 'down', 'from', 'getting', 'give', 'going', 'gonna', 
    'good', 'gotta', 'have', 'here', 'into', 'just', 'know', 'like', 'little',
    'look', 'make', 'mind', 'more', 'much', 'need', 'okay', 'only', 'onto',
    'other', 'over', 'part', 'pick', 'right', 'rock', 'roof', 'said', 'some',
    'stuff', 'take', 'talk', 'tell', 'than', 'that', 'them', 'then', 'there',
    'these', 'they', 'thing', 'things', 'think', 'this', 'time', 'today',
    'want', 'week', 'well', 'what', 'when', 'where', 'which', 'with', 'work',
    'would', 'yeah', 'your'
  ];
  v_words TEXT[];
BEGIN
  -- Extract words from transcript (lowercase, alpha only, min length, no stopwords)
  SELECT ARRAY_AGG(DISTINCT w) INTO v_words
  FROM (
    SELECT LOWER(REGEXP_REPLACE(word, '[^a-zA-Z]', '', 'g')) as w
    FROM UNNEST(STRING_TO_ARRAY(transcript_text, ' ')) as word
    WHERE LENGTH(REGEXP_REPLACE(word, '[^a-zA-Z]', '', 'g')) >= min_word_length
  ) t
  WHERE w != '' AND NOT (w = ANY(v_stopwords));

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
    -- Require higher scores for phonetic-only matches
    AND (fm.match_type NOT IN ('soundex', 'metaphone') OR fm.score >= 0.7)
  ORDER BY fm.project_id, v.word, fm.score DESC;
END;
$$ LANGUAGE plpgsql STABLE;;
