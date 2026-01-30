
-- v1.7.4 Pointer computation function
-- Handles both missing_pointer (use claim_text) and pointer_invalid (use span_text)

CREATE OR REPLACE FUNCTION compute_pointer_v174(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_claim RECORD;
  v_transcript text;
  v_search_text text;
  v_search_source text;
  v_found_pos int;
  v_clean_search text;
  v_clean_transcript text;
BEGIN
  -- Get claim with all relevant fields
  SELECT 
    jc.id,
    jc.call_id,
    jc.claim_text,
    jc.span_text,
    jc.char_start,
    jc.pointer_type
  INTO v_claim
  FROM journal_claims jc
  WHERE jc.id = p_claim_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'claim_not_found');
  END IF;
  
  -- Get transcript
  SELECT transcript INTO v_transcript 
  FROM calls_raw 
  WHERE interaction_id = v_claim.call_id;
  
  IF v_transcript IS NULL OR LENGTH(v_transcript) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'transcript_not_found');
  END IF;
  
  -- Decide which text to search for
  -- Priority: span_text > claim_text
  IF v_claim.span_text IS NOT NULL AND LENGTH(v_claim.span_text) > 10 THEN
    v_search_text := v_claim.span_text;
    v_search_source := 'span_text';
  ELSIF v_claim.claim_text IS NOT NULL AND LENGTH(v_claim.claim_text) > 10 THEN
    v_search_text := v_claim.claim_text;
    v_search_source := 'claim_text';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'no_searchable_text');
  END IF;
  
  -- Clean search text: strip speaker label prefix if present
  v_clean_search := v_search_text;
  IF v_clean_search LIKE '%:%' AND POSITION(':' IN v_clean_search) < 40 THEN
    v_clean_search := TRIM(SUBSTRING(v_clean_search FROM POSITION(':' IN v_clean_search) + 1));
  END IF;
  
  -- Strip leading ellipsis
  IF v_clean_search LIKE '...%' THEN
    v_clean_search := TRIM(SUBSTRING(v_clean_search FROM 4));
  END IF;
  
  -- Strategy 1: Exact match (case-insensitive)
  v_found_pos := POSITION(LOWER(v_clean_search) IN LOWER(v_transcript));
  
  -- Strategy 2: First 30 chars (handles truncation)
  IF v_found_pos = 0 AND LENGTH(v_clean_search) > 30 THEN
    v_found_pos := POSITION(LOWER(LEFT(v_clean_search, 30)) IN LOWER(v_transcript));
  END IF;
  
  -- Strategy 3: Normalized whitespace (newlines → spaces)
  IF v_found_pos = 0 THEN
    v_clean_transcript := REGEXP_REPLACE(v_transcript, '\s+', ' ', 'g');
    v_clean_search := REGEXP_REPLACE(v_clean_search, '\s+', ' ', 'g');
    v_found_pos := POSITION(LOWER(LEFT(v_clean_search, 30)) IN LOWER(v_clean_transcript));
  END IF;
  
  IF v_found_pos = 0 THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'span_not_found',
      'search_source', v_search_source,
      'search_preview', LEFT(v_clean_search, 50)
    );
  END IF;
  
  -- Update claim with computed pointer
  UPDATE journal_claims
  SET 
    char_start = v_found_pos,
    char_end = v_found_pos + LENGTH(v_clean_search),
    span_text = COALESCE(span_text, v_clean_search),
    span_hash = md5(v_clean_search),
    pointer_type = 'transcript_span'
  WHERE id = p_claim_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'char_start', v_found_pos,
    'char_end', v_found_pos + LENGTH(v_clean_search),
    'search_source', v_search_source,
    'search_preview', LEFT(v_clean_search, 50)
  );
END;
$$;

COMMENT ON FUNCTION compute_pointer_v174 IS 
'v1.7.4 pointer computation. Uses span_text or claim_text to find location in transcript.
Handles speaker labels, ellipsis, whitespace normalization. Updates char_start/char_end/span_hash.';
;
