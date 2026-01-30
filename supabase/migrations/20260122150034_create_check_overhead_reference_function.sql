-- Function to check if a transcript excerpt contains overhead reference
-- Returns true if the location mention is likely company infrastructure, not project

CREATE OR REPLACE FUNCTION check_overhead_reference(
  transcript_excerpt text,
  location_word text
) RETURNS boolean AS $$
DECLARE
  overhead_indicators text[] := ARRAY[
    'my shop', 'the shop', 'our shop',
    'my office', 'the office', 'our office', 
    'my yard', 'the yard', 'our yard',
    'my warehouse', 'the warehouse', 'our warehouse',
    'my truck', 'the truck', 'our truck',
    'shop''s in', 'shop is in', 'office is in'
  ];
  indicator text;
  excerpt_lower text;
BEGIN
  excerpt_lower := LOWER(transcript_excerpt);
  
  -- Check if location word is near any overhead indicator
  FOREACH indicator IN ARRAY overhead_indicators
  LOOP
    -- If indicator appears within 50 chars of location word
    IF excerpt_lower LIKE '%' || indicator || '%' 
       AND excerpt_lower LIKE '%' || LOWER(location_word) || '%'
       AND ABS(
         POSITION(indicator IN excerpt_lower) - 
         POSITION(LOWER(location_word) IN excerpt_lower)
       ) < 50
    THEN
      RETURN true;
    END IF;
  END LOOP;
  
  -- Also check if location matches a known company anchor
  IF EXISTS (
    SELECT 1 FROM company_anchors 
    WHERE LOWER(location_city) = LOWER(location_word)
  ) AND (
    excerpt_lower LIKE '%shop%' OR
    excerpt_lower LIKE '%office%' OR
    excerpt_lower LIKE '%yard%' OR
    excerpt_lower LIKE '%warehouse%'
  ) THEN
    RETURN true;
  END IF;
  
  RETURN false;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION check_overhead_reference IS 
  'Returns true if transcript excerpt suggests location is company infrastructure (shop, office, yard) rather than project site. Used by alias scanner to filter false positives.';;
