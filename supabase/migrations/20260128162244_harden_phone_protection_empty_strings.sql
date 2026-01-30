
-- Harden trigger to treat empty strings as null-equivalent
-- This prevents empty strings from being treated as "values" that survive COALESCE
CREATE OR REPLACE FUNCTION protect_phone_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Normalize empty strings to NULL first
  NEW.other_party_phone := NULLIF(TRIM(NEW.other_party_phone), '');
  NEW.owner_phone := NULLIF(TRIM(NEW.owner_phone), '');
  NEW.other_party_name := NULLIF(TRIM(NEW.other_party_name), '');
  NEW.owner_name := NULLIF(TRIM(NEW.owner_name), '');
  
  -- Then preserve: never overwrite non-null with null
  NEW.other_party_phone := COALESCE(NEW.other_party_phone, OLD.other_party_phone);
  NEW.owner_phone := COALESCE(NEW.owner_phone, OLD.owner_phone);
  NEW.other_party_name := COALESCE(NEW.other_party_name, OLD.other_party_name);
  NEW.owner_name := COALESCE(NEW.owner_name, OLD.owner_name);
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION protect_phone_fields IS 
'BEFORE UPDATE trigger on calls_raw. Normalizes empty strings to NULL, then COALESCE preserves existing non-null values. Prevents regression on reruns.';
;
