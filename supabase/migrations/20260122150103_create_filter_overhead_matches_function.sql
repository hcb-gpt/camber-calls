-- Function to filter alias scan results, removing overhead references
-- This is applied AFTER scan_transcript_for_projects to remove false positives

CREATE OR REPLACE FUNCTION filter_overhead_matches(
  transcript_text text,
  matches jsonb  -- Array of {project_id, matched_term, ...}
) RETURNS jsonb AS $$
DECLARE
  filtered_matches jsonb := '[]'::jsonb;
  match_record jsonb;
  matched_term text;
  context_window text;
  term_position int;
BEGIN
  -- Process each match
  FOR match_record IN SELECT * FROM jsonb_array_elements(matches)
  LOOP
    matched_term := match_record->>'matched_term';
    
    -- Find position of matched term in transcript
    term_position := POSITION(LOWER(matched_term) IN LOWER(transcript_text));
    
    IF term_position > 0 THEN
      -- Extract context window (100 chars before and after)
      context_window := SUBSTRING(
        transcript_text 
        FROM GREATEST(1, term_position - 100) 
        FOR 200 + LENGTH(matched_term)
      );
      
      -- Check if this is an overhead reference
      IF NOT check_overhead_reference(context_window, matched_term) THEN
        -- Keep this match
        filtered_matches := filtered_matches || match_record;
      END IF;
    ELSE
      -- Term not found (shouldn't happen), keep it anyway
      filtered_matches := filtered_matches || match_record;
    END IF;
  END LOOP;
  
  RETURN filtered_matches;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION filter_overhead_matches IS 
  'Filters alias scan results to remove matches that are company overhead references (shop, office, yard). Applied after scan_transcript_for_projects.';;
