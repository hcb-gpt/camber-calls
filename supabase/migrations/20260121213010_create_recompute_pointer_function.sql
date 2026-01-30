
-- Function to recompute pointer for a claim by finding span_text in transcript
CREATE OR REPLACE FUNCTION recompute_claim_pointer(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_claim journal_claims%ROWTYPE;
  v_transcript text;
  v_search_text text;
  v_found_pos int;
BEGIN
  -- Get claim
  SELECT * INTO v_claim FROM journal_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'claim not found');
  END IF;
  
  -- Get transcript
  SELECT transcript INTO v_transcript FROM calls_raw WHERE interaction_id = v_claim.call_id;
  IF v_transcript IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'transcript not found');
  END IF;
  
  -- Prepare search text (strip speaker label if present)
  v_search_text := v_claim.span_text;
  IF v_search_text LIKE '%:%' THEN
    v_search_text := TRIM(SUBSTRING(v_search_text FROM POSITION(':' IN v_search_text) + 1));
  END IF;
  
  -- Strip leading ellipsis if present
  IF v_search_text LIKE '...%' THEN
    v_search_text := TRIM(SUBSTRING(v_search_text FROM 4));
  END IF;
  
  -- Find position (case-insensitive)
  v_found_pos := POSITION(LOWER(v_search_text) IN LOWER(v_transcript));
  
  IF v_found_pos = 0 THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'span not found in transcript',
      'search_text', LEFT(v_search_text, 50)
    );
  END IF;
  
  -- Update claim with computed pointer
  UPDATE journal_claims
  SET 
    char_start = v_found_pos,
    char_end = v_found_pos + LENGTH(v_search_text),
    span_hash = md5(v_search_text),
    pointer_type = 'transcript_span'
  WHERE id = p_claim_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'char_start', v_found_pos,
    'char_end', v_found_pos + LENGTH(v_search_text),
    'search_text', LEFT(v_search_text, 50)
  );
END;
$$;

COMMENT ON FUNCTION recompute_claim_pointer IS 
'Recomputes char_start/char_end/span_hash for a claim by finding span_text in transcript. 
Strips speaker label prefix and leading ellipsis before searching.';
;
