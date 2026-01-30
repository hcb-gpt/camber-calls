-- Trigger: Auto-resolve speaker_contact_id and reported_by_contact_id on insert/update

CREATE OR REPLACE FUNCTION resolve_journal_claim_speakers()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_speaker_result RECORD;
  v_reported_by_result RECORD;
BEGIN
  -- Resolve speaker_label if present and not already resolved
  IF NEW.speaker_label IS NOT NULL AND NEW.speaker_contact_id IS NULL THEN
    SELECT * INTO v_speaker_result 
    FROM resolve_speaker_contact(NEW.speaker_label, NEW.claim_project_id);
    
    IF v_speaker_result.contact_id IS NOT NULL THEN
      NEW.speaker_contact_id := v_speaker_result.contact_id;
      NEW.speaker_is_internal := v_speaker_result.is_internal;
    END IF;
  END IF;
  
  -- Resolve reported_by_label if present and not already resolved
  IF NEW.reported_by_label IS NOT NULL AND NEW.reported_by_contact_id IS NULL THEN
    SELECT * INTO v_reported_by_result 
    FROM resolve_speaker_contact(NEW.reported_by_label, NEW.claim_project_id);
    
    IF v_reported_by_result.contact_id IS NOT NULL THEN
      NEW.reported_by_contact_id := v_reported_by_result.contact_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Drop existing trigger if any
DROP TRIGGER IF EXISTS trg_resolve_journal_claim_speakers ON journal_claims;

-- Create trigger
CREATE TRIGGER trg_resolve_journal_claim_speakers
  BEFORE INSERT OR UPDATE ON journal_claims
  FOR EACH ROW
  EXECUTE FUNCTION resolve_journal_claim_speakers();

COMMENT ON FUNCTION resolve_journal_claim_speakers IS 
'Auto-resolves speaker_label and reported_by_label to contact_ids on journal_claims insert/update.
Uses resolve_speaker_contact RPC for fuzzy matching.';;
