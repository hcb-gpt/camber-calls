-- Update engagement score function per STRATA spec
-- Formula: (interaction_count * 1.0) + (total_transcript_chars / 150 * 0.5)
-- Also adds auto-flagging for is_key_contact

CREATE OR REPLACE FUNCTION recompute_contact_engagement_score()
RETURNS TRIGGER AS $$
DECLARE
  transcript_minutes NUMERIC;
BEGIN
  -- Calculate transcript minutes (approx 150 chars per minute)
  transcript_minutes := COALESCE(NEW.total_transcript_chars, 0) / 150.0;
  
  -- STRATA formula: (interaction_count * 1.0) + (transcript_minutes * 0.5)
  NEW.engagement_score := (
    COALESCE(NEW.interaction_count, 0) * 1.0
    + transcript_minutes * 0.5
  );
  
  -- Auto-flag is_key_contact if criteria met (unless manual override exists)
  IF NEW.key_contact_reason IS NULL THEN
    IF COALESCE(NEW.total_transcript_chars, 0) > 50000 
       OR COALESCE(NEW.interaction_count, 0) > 20 THEN
      NEW.is_key_contact := TRUE;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;;
