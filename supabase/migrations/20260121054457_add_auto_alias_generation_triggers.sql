-- Function to generate client name aliases when affinity is created/updated
CREATE OR REPLACE FUNCTION generate_client_aliases()
RETURNS TRIGGER AS $$
DECLARE
  v_contact RECORD;
  v_first_name TEXT;
  v_last_name TEXT;
BEGIN
  -- Only process if weight > 0 (strong affinity)
  IF NEW.weight <= 0 THEN
    RETURN NEW;
  END IF;

  -- Get contact details
  SELECT * INTO v_contact FROM contacts WHERE id = NEW.contact_id;
  
  -- Only for clients
  IF v_contact.contact_type != 'client' THEN
    RETURN NEW;
  END IF;

  v_first_name := LOWER(SPLIT_PART(v_contact.name, ' ', 1));
  v_last_name := LOWER(SPLIT_PART(v_contact.name, ' ', 2));

  -- Add first name alias if not exists
  IF v_first_name != '' THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.project_id, v_first_name, 'client_first_name', 'auto_generated', 0.9, NOW(), 'trigger')
    ON CONFLICT DO NOTHING;
  END IF;

  -- Add last name alias if not exists
  IF v_last_name != '' THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.project_id, v_last_name, 'client_last_name', 'auto_generated', 0.95, NOW(), 'trigger')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on correspondent_project_affinity
DROP TRIGGER IF EXISTS trg_generate_client_aliases ON correspondent_project_affinity;
CREATE TRIGGER trg_generate_client_aliases
  AFTER INSERT OR UPDATE ON correspondent_project_affinity
  FOR EACH ROW
  EXECUTE FUNCTION generate_client_aliases();

-- Function to generate street name aliases when project is created/updated
CREATE OR REPLACE FUNCTION generate_street_aliases()
RETURNS TRIGGER AS $$
DECLARE
  v_street_name TEXT;
  v_short_name TEXT;
  v_first_word TEXT;
BEGIN
  -- Only if street changed and is not null
  IF NEW.street IS NULL OR NEW.street = '' THEN
    RETURN NEW;
  END IF;
  
  IF TG_OP = 'UPDATE' AND OLD.street = NEW.street THEN
    RETURN NEW;
  END IF;

  -- Extract street name (remove leading numbers and trailing suffixes)
  v_street_name := LOWER(TRIM(REGEXP_REPLACE(
    REGEXP_REPLACE(NEW.street, '^[0-9]+\s+', ''),
    '\s+(Rd|Road|Dr|Drive|St|Street|Ct|Court|Ave|Avenue|Ln|Lane|Way|Blvd|Boulevard|Cir|Circle|Pl|Place)\.?$',
    '', 'i'
  )));

  -- Add full street name
  IF v_street_name != '' THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.id, v_street_name, 'street_name', 'auto_generated', 0.85, NOW(), 'trigger')
    ON CONFLICT DO NOTHING;

    -- Add shortened version (first 2 words if 3+ words)
    IF array_length(string_to_array(v_street_name, ' '), 1) >= 3 THEN
      v_short_name := (string_to_array(v_street_name, ' '))[1] || ' ' || (string_to_array(v_street_name, ' '))[2];
      INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
      VALUES (gen_random_uuid(), NEW.id, v_short_name, 'street_name_short', 'auto_generated', 0.85, NOW(), 'trigger')
      ON CONFLICT DO NOTHING;
    END IF;

    -- Add first word only (lower confidence)
    v_first_word := (string_to_array(v_street_name, ' '))[1];
    IF v_first_word != '' AND LENGTH(v_first_word) > 3 THEN
      INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
      VALUES (gen_random_uuid(), NEW.id, v_first_word, 'street_name_short', 'auto_generated', 0.75, NOW(), 'trigger')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on projects
DROP TRIGGER IF EXISTS trg_generate_street_aliases ON projects;
CREATE TRIGGER trg_generate_street_aliases
  AFTER INSERT OR UPDATE OF street ON projects
  FOR EACH ROW
  EXECUTE FUNCTION generate_street_aliases();

COMMENT ON FUNCTION generate_client_aliases() IS 'Auto-generates first/last name aliases when client affinity is created';
COMMENT ON FUNCTION generate_street_aliases() IS 'Auto-generates street name aliases when project street is set';;
