-- Enhanced trigger function: adds city and county aliases
CREATE OR REPLACE FUNCTION trg_auto_generate_street_aliases()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_street_full TEXT;
  v_street_short TEXT;
  v_street_first TEXT;
  v_words TEXT[];
  v_name_stem TEXT;
  v_city TEXT;
  v_county TEXT;
BEGIN
  -- ============================================
  -- PART 1: Project name stem alias
  -- ============================================
  IF NEW.name LIKE '% Residence%' THEN
    v_name_stem := LOWER(TRIM(SPLIT_PART(SPLIT_PART(NEW.name, ' Residence', 1), ' (', 1)));
    IF v_name_stem != '' THEN
      INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
      VALUES (gen_random_uuid(), NEW.id, v_name_stem, 'project_name_stem', 'auto_trigger', 0.95, NOW(), 'trg_auto_generate_street_aliases')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- ============================================
  -- PART 2: City alias (NEW)
  -- ============================================
  v_city := TRIM(NEW.city);
  IF v_city IS NOT NULL AND v_city != '' THEN
    -- Only insert if city changed or this is an INSERT
    IF TG_OP = 'INSERT' OR OLD.city IS DISTINCT FROM NEW.city THEN
      INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
      VALUES (gen_random_uuid(), NEW.id, v_city, 'location', 'auto_trigger', 0.80, NOW(), 'trg_auto_generate_street_aliases')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- ============================================
  -- PART 3: County alias (NEW)
  -- ============================================
  v_county := TRIM(NEW.county);
  IF v_county IS NOT NULL AND v_county != '' THEN
    -- Only insert if county changed or this is an INSERT
    IF TG_OP = 'INSERT' OR OLD.county IS DISTINCT FROM NEW.county THEN
      INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
      VALUES (gen_random_uuid(), NEW.id, v_county, 'county', 'auto_trigger', 0.80, NOW(), 'trg_auto_generate_street_aliases')
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- ============================================
  -- PART 4: Street name aliases (existing logic)
  -- ============================================
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
$function$;

COMMENT ON FUNCTION trg_auto_generate_street_aliases() IS 
'Auto-generates project aliases from: (1) project name stem, (2) city, (3) county, (4) street name variants. v2.0 - added city/county support 2026-01-22';;
