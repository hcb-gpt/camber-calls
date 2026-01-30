-- Update compute_pointer to handle more speaker label formats including "(work)", "(personal)", etc.
CREATE OR REPLACE FUNCTION compute_pointer_v174(p_claim_id uuid)
RETURNS jsonb AS $$
DECLARE
  v_claim RECORD;
  v_transcript text;
  v_search_text text;
  v_search_source text;
  v_found_pos int;
  v_clean_search text;
  v_clean_transcript text;
BEGIN
  SELECT jc.id, jc.call_id, jc.claim_text, jc.span_text, jc.char_start, jc.pointer_type
  INTO v_claim FROM journal_claims jc WHERE jc.id = p_claim_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'claim_not_found');
  END IF;
  
  SELECT transcript INTO v_transcript FROM calls_raw WHERE interaction_id = v_claim.call_id;
  
  IF v_transcript IS NULL OR LENGTH(v_transcript) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'transcript_not_found');
  END IF;
  
  -- Pick search text
  IF v_claim.span_text IS NOT NULL AND LENGTH(v_claim.span_text) > 10 THEN
    v_search_text := v_claim.span_text;
    v_search_source := 'span_text';
  ELSIF v_claim.claim_text IS NOT NULL AND LENGTH(v_claim.claim_text) > 10 THEN
    v_search_text := v_claim.claim_text;
    v_search_source := 'claim_text';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'text_too_short', 'claim_text', v_claim.claim_text);
  END IF;
  
  -- Clean search text: strip speaker label prefix (handles "Name:", "Name (work):", etc.)
  v_clean_search := v_search_text;
  -- Strip "Speaker Name (anything):" pattern
  v_clean_search := REGEXP_REPLACE(v_clean_search, E'^[A-Za-z ]+\\s*(\\([^)]*\\))?\\s*:\\s*', '', 'g');
  -- Strip leading "..."
  IF v_clean_search LIKE '...%' THEN
    v_clean_search := TRIM(SUBSTRING(v_clean_search FROM 4));
  END IF;
  
  -- Normalize both
  v_clean_search := LOWER(v_clean_search);
  v_clean_search := TRANSLATE(v_clean_search, E'\u2018\u2019\u201C\u201D', '''''""');
  
  v_clean_transcript := LOWER(v_transcript);
  v_clean_transcript := TRANSLATE(v_clean_transcript, E'\u2018\u2019\u201C\u201D', '''''""');
  
  -- Strategy 1: Exact match
  v_found_pos := POSITION(v_clean_search IN v_clean_transcript);
  
  -- Strategy 2: First 30 chars
  IF v_found_pos = 0 AND LENGTH(v_clean_search) > 30 THEN
    v_found_pos := POSITION(LEFT(v_clean_search, 30) IN v_clean_transcript);
  END IF;
  
  -- Strategy 3: Whitespace normalized
  IF v_found_pos = 0 THEN
    v_clean_transcript := REGEXP_REPLACE(v_clean_transcript, E'\\s+', ' ', 'g');
    v_clean_search := REGEXP_REPLACE(v_clean_search, E'\\s+', ' ', 'g');
    v_found_pos := POSITION(LEFT(v_clean_search, 30) IN v_clean_transcript);
  END IF;
  
  -- Strategy 4: Strip punctuation
  IF v_found_pos = 0 THEN
    v_clean_transcript := REGEXP_REPLACE(v_clean_transcript, E'[^a-z0-9\\s]', '', 'g');
    v_clean_search := REGEXP_REPLACE(v_clean_search, E'[^a-z0-9\\s]', '', 'g');
    v_found_pos := POSITION(LEFT(v_clean_search, 25) IN v_clean_transcript);
  END IF;
  
  -- Strategy 5: Strip ALL speaker labels from transcript
  IF v_found_pos = 0 THEN
    -- Remove "Speaker Name (tag):" patterns from transcript
    v_clean_transcript := REGEXP_REPLACE(LOWER(v_transcript), E'[A-Za-z ]+\\s*(\\([^)]*\\))?\\s*:', '', 'g');
    v_clean_transcript := REGEXP_REPLACE(v_clean_transcript, E'\\s+', ' ', 'g');
    v_clean_search := REGEXP_REPLACE(LOWER(v_search_text), E'^[A-Za-z ]+\\s*(\\([^)]*\\))?\\s*:\\s*', '', 'g');
    v_clean_search := REGEXP_REPLACE(v_clean_search, E'\\s+', ' ', 'g');
    v_found_pos := POSITION(LEFT(v_clean_search, 25) IN v_clean_transcript);
  END IF;
  
  IF v_found_pos = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'span_not_found',
      'search_source', v_search_source, 'search_preview', LEFT(v_clean_search, 50));
  END IF;
  
  UPDATE journal_claims
  SET char_start = v_found_pos,
      char_end = v_found_pos + LENGTH(v_clean_search),
      span_text = COALESCE(span_text, v_clean_search),
      span_hash = md5(v_clean_search),
      pointer_type = 'transcript_span'
  WHERE id = p_claim_id;
  
  RETURN jsonb_build_object('success', true, 'char_start', v_found_pos,
    'char_end', v_found_pos + LENGTH(v_clean_search), 'search_source', v_search_source);
END;
$$ LANGUAGE plpgsql;;
