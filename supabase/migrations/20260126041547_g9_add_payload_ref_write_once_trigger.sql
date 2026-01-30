-- G9: payload_ref write-once trigger
-- Once payload_ref is set, it cannot be changed

CREATE OR REPLACE FUNCTION enforce_payload_ref_write_once()
RETURNS TRIGGER AS $$
BEGIN
  -- If OLD.payload_ref was set (not NULL), and NEW.payload_ref differs, reject
  IF OLD.payload_ref IS NOT NULL AND NEW.payload_ref IS DISTINCT FROM OLD.payload_ref THEN
    RAISE EXCEPTION 'G9 VIOLATION: payload_ref is write-once and cannot be mutated. evidence_event_id=%', OLD.evidence_event_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payload_ref_write_once
  BEFORE UPDATE ON evidence_events
  FOR EACH ROW
  EXECUTE FUNCTION enforce_payload_ref_write_once();

COMMENT ON TRIGGER trg_payload_ref_write_once ON evidence_events IS 
'G9 invariant: payload_ref cannot be mutated once set. This ensures evidence immutability.';;
