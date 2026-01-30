-- Trigger to recompute engagement_score when relevant fields change
CREATE OR REPLACE FUNCTION recompute_contact_engagement_score()
RETURNS TRIGGER AS $$
BEGIN
  NEW.engagement_score := (
    COALESCE(NEW.total_transcript_chars, 0) / 1000.0
    * CASE WHEN NEW.contact_type IN ('subcontractor', 'supplier') THEN 2.0 ELSE 1.0 END
    + CASE WHEN NEW.is_key_contact = true THEN 500 ELSE 0 END
    + CASE WHEN NEW.last_interaction_at > NOW() - INTERVAL '7 days' THEN 50 ELSE 0 END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contact_engagement_score
BEFORE INSERT OR UPDATE OF total_transcript_chars, contact_type, is_key_contact, last_interaction_at
ON contacts
FOR EACH ROW
EXECUTE FUNCTION recompute_contact_engagement_score();;
