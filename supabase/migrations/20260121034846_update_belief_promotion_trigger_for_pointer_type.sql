-- Update belief promotion trigger to use pointer_type instead of start_sec/end_sec
-- v1: Only 'transcript_span' is promotable without review approval

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
  SELECT pointer_type, char_start, char_end, span_hash INTO source_claim
  FROM journal_claims
  WHERE id = NEW.journal_claim_id;

  -- v1 PROMOTABLE: transcript_span with valid char pointers
  IF source_claim.pointer_type = 'transcript_span' 
     AND source_claim.char_start IS NOT NULL 
     AND source_claim.char_end IS NOT NULL 
     AND source_claim.span_hash IS NOT NULL THEN
    RETURN NEW;  -- Has valid transcript span, OK to promote
  END IF;

  -- v2 FUTURE: audio_span would go here when implemented
  -- IF source_claim.pointer_type = 'audio_span' AND ... THEN RETURN NEW; END IF;

  -- No valid pointer - check if explicitly approved via review queue
  SELECT EXISTS (
    SELECT 1 FROM journal_review_queue
    WHERE item_id = NEW.journal_claim_id
      AND item_type = 'claim'
      AND status = 'approved'
  ) INTO review_approved;

  IF review_approved THEN
    RETURN NEW;  -- Approved in review, OK to promote
  END IF;

  -- Neither valid pointers nor review approval - block promotion
  RAISE EXCEPTION 'Cannot promote claim % without valid transcript_span pointer (char_start/char_end/span_hash) or review approval. pointer_type=%', 
    NEW.journal_claim_id, source_claim.pointer_type;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_belief_promotion_pointers() IS 'Enforces P2 stop-line: beliefs must have transcript_span pointers OR review approval. v1 uses char-based spans, not hallucinated seconds.';;
