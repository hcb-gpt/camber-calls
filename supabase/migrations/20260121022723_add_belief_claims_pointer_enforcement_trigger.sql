-- Trigger to enforce: promoted beliefs require pointers OR explicit review approval
-- "Promoted belief requires pointers (or explicit review routing)"

CREATE OR REPLACE FUNCTION check_belief_promotion_pointers()
RETURNS TRIGGER AS $$
DECLARE
  source_claim RECORD;
  review_approved BOOLEAN;
BEGIN
  -- If no journal_claim_id, skip check (legacy data or direct insert)
  IF NEW.journal_claim_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Get source claim's pointer status
  SELECT start_sec, end_sec INTO source_claim
  FROM journal_claims
  WHERE id = NEW.journal_claim_id;

  -- Check if pointers exist
  IF source_claim.start_sec IS NOT NULL AND source_claim.end_sec IS NOT NULL THEN
    RETURN NEW;  -- Has pointers, OK to promote
  END IF;

  -- No pointers - check if explicitly approved via review queue
  SELECT EXISTS (
    SELECT 1 FROM journal_review_queue
    WHERE item_id = NEW.journal_claim_id
      AND item_type = 'claim'
      AND status = 'approved'
  ) INTO review_approved;

  IF review_approved THEN
    RETURN NEW;  -- Approved in review, OK to promote
  END IF;

  -- Neither pointers nor review approval - block promotion
  RAISE EXCEPTION 'Cannot promote claim % without pointers (start_sec/end_sec) or review approval', NEW.journal_claim_id;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER belief_claims_pointer_enforcement
  BEFORE INSERT ON belief_claims
  FOR EACH ROW
  EXECUTE FUNCTION check_belief_promotion_pointers();

COMMENT ON FUNCTION check_belief_promotion_pointers() IS 'Enforces P2 stop-line: beliefs must have transcript pointers OR explicit review approval';;
