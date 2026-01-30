-- Function to auto-generate aliases when client contacts get project affinity
CREATE OR REPLACE FUNCTION public.trg_auto_generate_client_aliases()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_contact RECORD;
  v_first_name TEXT;
  v_last_name TEXT;
BEGIN
  -- Only process if weight > 0 (confirmed affinity)
  IF NEW.weight <= 0 THEN
    RETURN NEW;
  END IF;

  -- Get contact details
  SELECT * INTO v_contact
  FROM contacts
  WHERE id = NEW.contact_id
    AND contact_type = 'client';

  -- Skip if not a client
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Extract names
  v_first_name := LOWER(TRIM(SPLIT_PART(v_contact.name, ' ', 1)));
  v_last_name := LOWER(TRIM(SPLIT_PART(v_contact.name, ' ', 2)));

  -- Add first name alias (if not empty and doesn't exist)
  IF v_first_name != '' THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.project_id, v_first_name, 'client_first_name', 'auto_trigger', 0.9, NOW(), 'trg_auto_generate_client_aliases')
    ON CONFLICT DO NOTHING;
  END IF;

  -- Add last name alias (if not empty and doesn't exist)
  IF v_last_name != '' THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.project_id, v_last_name, 'client_last_name', 'auto_trigger', 0.95, NOW(), 'trg_auto_generate_client_aliases')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger on correspondent_project_affinity INSERT/UPDATE
DROP TRIGGER IF EXISTS trg_auto_client_aliases ON correspondent_project_affinity;
CREATE TRIGGER trg_auto_client_aliases
  AFTER INSERT OR UPDATE ON correspondent_project_affinity
  FOR EACH ROW
  EXECUTE FUNCTION trg_auto_generate_client_aliases();

COMMENT ON FUNCTION public.trg_auto_generate_client_aliases() IS 
'Auto-generates first/last name aliases when client contacts gain project affinity.';;
