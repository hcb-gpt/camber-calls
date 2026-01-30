-- Protect phone fields from null-overwrites on rerun
CREATE OR REPLACE FUNCTION protect_phone_fields()
RETURNS TRIGGER AS $$
BEGIN
  -- Preserve phones: never overwrite non-null with null
  NEW.other_party_phone := COALESCE(NEW.other_party_phone, OLD.other_party_phone);
  NEW.owner_phone := COALESCE(NEW.owner_phone, OLD.owner_phone);
  NEW.other_party_name := COALESCE(NEW.other_party_name, OLD.other_party_name);
  NEW.owner_name := COALESCE(NEW.owner_name, OLD.owner_name);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_phone_fields
  BEFORE UPDATE ON calls_raw
  FOR EACH ROW
  EXECUTE FUNCTION protect_phone_fields();;
