-- CRITICAL FIX: Orphan Stopline Trigger
-- Per STRATA-25 directive 2026-01-26_0605Z
-- Root cause: trigger checked journal_claims.id instead of journal_claims.claim_id

CREATE OR REPLACE FUNCTION check_review_queue_claim_exists()
RETURNS TRIGGER AS $$
BEGIN
  -- Conflict entries have synthetic IDs, exempt from FK check
  IF NEW.reason = 'conflict' THEN
    RETURN NEW;
  END IF;
  
  -- Fixed: Check claim_id instead of id
  IF NOT EXISTS (SELECT 1 FROM journal_claims WHERE claim_id = NEW.item_id) THEN
    RAISE EXCEPTION 'review_queue item_id % does not exist in journal_claims (reason: %)', 
      NEW.item_id, NEW.reason;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_review_queue_claim_exists IS 
'Orphan stopline: prevents review_queue items referencing non-existent journal_claims. Fixed 2026-01-26 to check claim_id column.';;
