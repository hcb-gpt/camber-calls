-- Trigger to auto-update contact interaction stats on new interactions
CREATE OR REPLACE FUNCTION update_contact_interaction_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.contact_id IS NOT NULL THEN
    UPDATE contacts SET
      interaction_count = COALESCE(interaction_count, 0) + 1,
      last_interaction_at = GREATEST(COALESCE(last_interaction_at, '1970-01-01'::timestamptz), NEW.event_at_utc),
      updated_at = now()
    WHERE id = NEW.contact_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_interaction_contact_stats
AFTER INSERT ON interactions
FOR EACH ROW
EXECUTE FUNCTION update_contact_interaction_stats();

COMMENT ON FUNCTION update_contact_interaction_stats() IS 'Auto-increment contact interaction_count and update last_interaction_at on new interactions';;
