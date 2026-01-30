-- Function to auto-generate street aliases when projects are created/updated
CREATE OR REPLACE FUNCTION public.trg_auto_generate_street_aliases()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_street_full TEXT;
  v_street_short TEXT;
  v_street_first TEXT;
  v_words TEXT[];
BEGIN
  -- Only if street is set and changed
  IF NEW.street IS NULL OR TRIM(NEW.street) = '' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.street IS NOT DISTINCT FROM NEW.street THEN
    RETURN NEW;
  END IF;

  -- Extract street name: remove leading numbers and trailing suffixes
  v_street_full := LOWER(TRIM(REGEXP_REPLACE(
    REGEXP_REPLACE(NEW.street, '^[0-9]+\s+', ''),
    '\s+(Rd|Road|Dr|Drive|St|Street|Ct|Court|Ave|Avenue|Ln|Lane|Way|Blvd|Boulevard|Cir|Circle|Pl|Place)\.?$',
    '', 'i'
  )));

  IF v_street_full = '' THEN
    RETURN NEW;
  END IF;

  -- Full street name alias
  INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
  VALUES (gen_random_uuid(), NEW.id, v_street_full, 'street_name', 'auto_trigger', 0.85, NOW(), 'trg_auto_generate_street_aliases')
  ON CONFLICT DO NOTHING;

  -- Split into words
  v_words := string_to_array(v_street_full, ' ');

  -- First two words if 3+ words (e.g., "hickory grove church" → "hickory grove")
  IF array_length(v_words, 1) >= 3 THEN
    v_street_short := v_words[1] || ' ' || v_words[2];
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.id, v_street_short, 'street_name_short', 'auto_trigger', 0.85, NOW(), 'trg_auto_generate_street_aliases')
    ON CONFLICT DO NOTHING;
  END IF;

  -- First word only if > 3 chars (e.g., "hickory")
  v_street_first := v_words[1];
  IF LENGTH(v_street_first) > 3 THEN
    INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
    VALUES (gen_random_uuid(), NEW.id, v_street_first, 'street_name_short', 'auto_trigger', 0.75, NOW(), 'trg_auto_generate_street_aliases')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger on projects INSERT/UPDATE
DROP TRIGGER IF EXISTS trg_auto_street_aliases ON projects;
CREATE TRIGGER trg_auto_street_aliases
  AFTER INSERT OR UPDATE OF street ON projects
  FOR EACH ROW
  EXECUTE FUNCTION trg_auto_generate_street_aliases();

COMMENT ON FUNCTION public.trg_auto_generate_street_aliases() IS 
'Auto-generates street name aliases (full, short, first-word) when project street is set.';;
