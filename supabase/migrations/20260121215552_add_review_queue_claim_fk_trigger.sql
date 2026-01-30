
-- FK-like constraint via trigger (exempts conflict-type entries)
-- STRAT Decision 2026-01-21: Approved Option A - keep conflicts, exempt from FK

CREATE OR REPLACE FUNCTION check_review_queue_claim_exists()
RETURNS TRIGGER AS $$
BEGIN
  -- Conflict entries have synthetic IDs, exempt from FK check
  IF NEW.reason = 'conflict' THEN
    RETURN NEW;
  END IF;
  
  -- All other entries must reference existing journal_claims
  IF NOT EXISTS (SELECT 1 FROM journal_claims WHERE id = NEW.item_id) THEN
    RAISE EXCEPTION 'review_queue item_id % does not exist in journal_claims (reason: %)', 
      NEW.item_id, NEW.reason;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop if exists and recreate
DROP TRIGGER IF EXISTS trg_check_review_queue_claim ON journal_review_queue;

CREATE TRIGGER trg_check_review_queue_claim
BEFORE INSERT OR UPDATE ON journal_review_queue
FOR EACH ROW EXECUTE FUNCTION check_review_queue_claim_exists();

COMMENT ON FUNCTION check_review_queue_claim_exists IS 
'Enforces FK-like constraint: item_id must exist in journal_claims, except for conflict-type entries which have synthetic IDs.';
;
