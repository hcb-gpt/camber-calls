
-- Harden phone protection to also reject empty strings
-- NULLIF converts '' to NULL, then COALESCE preserves OLD value

CREATE OR REPLACE FUNCTION protect_phone_fields()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Preserve phones: never overwrite non-null with null OR empty string
  NEW.other_party_phone := NULLIF(COALESCE(NULLIF(NEW.other_party_phone, ''), OLD.other_party_phone), '');
  NEW.owner_phone := NULLIF(COALESCE(NULLIF(NEW.owner_phone, ''), OLD.owner_phone), '');
  NEW.other_party_name := NULLIF(COALESCE(NULLIF(NEW.other_party_name, ''), OLD.other_party_name), '');
  NEW.owner_name := NULLIF(COALESCE(NULLIF(NEW.owner_name, ''), OLD.owner_name), '');
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION protect_phone_fields() IS 
'BEFORE UPDATE trigger on calls_raw. Prevents regression of phone/name fields.
Logic: NULLIF(incoming, '''') converts empty to NULL, COALESCE preserves OLD if NULL, 
outer NULLIF ensures we never store empty strings. Updated 2026-01-28 to block empty strings.';
;
