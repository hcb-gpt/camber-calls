-- Update the interaction stats trigger to accumulate transcript chars
CREATE OR REPLACE FUNCTION update_contact_interaction_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.contact_id IS NOT NULL THEN
    UPDATE contacts SET
      interaction_count = COALESCE(interaction_count, 0) + 1,
      last_interaction_at = GREATEST(COALESCE(last_interaction_at, '1970-01-01'::timestamptz), NEW.event_at_utc),
      total_transcript_chars = COALESCE(total_transcript_chars, 0) + COALESCE(NEW.transcript_chars, 0),
      updated_at = now()
    WHERE id = NEW.contact_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;;
