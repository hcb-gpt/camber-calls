
-- 3. Auto-flag is_key_contact based on criteria
CREATE OR REPLACE FUNCTION auto_flag_key_contact()
RETURNS TRIGGER AS $$
BEGIN
  -- Auto-flag if meets criteria (unless manually set with reason)
  IF NEW.key_contact_reason IS NULL THEN
    IF NEW.total_transcript_chars > 50000 AND NEW.interaction_count > 20 THEN
      NEW.is_key_contact := TRUE;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop if exists and recreate
DROP TRIGGER IF EXISTS trg_auto_flag_key_contact ON contacts;

CREATE TRIGGER trg_auto_flag_key_contact
BEFORE UPDATE ON contacts
FOR EACH ROW
EXECUTE FUNCTION auto_flag_key_contact();
;
