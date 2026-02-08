-- Fix: first_name_prefix must not bypass last-name gating
-- Receipt: fix_first_name_prefix_v1_verified (DATA)
-- Bug: "Dennis Sittler" matched "Dennis Chapman" via first_name_prefix (q=70)
--       because prefix match ignored last name entirely.
--
-- Changes:
--   1. Suppress first_name_prefix when v_last_name != '' AND contact's last name
--      does not match (exact or phonetic) — prefix must not bypass last-name gating
--   2. Add surname phonetic path (q=72) for STT misspellings:
--      Cotrell→Cottrell, Tredaway→Treadaway
--   3. Downgrade first-name-only prefix (no last name) from 70→65
--
-- Eliminates 3 false matches: Dennis Sittler→Chapman, Aleah Sittler prefix,
-- Zachary Sittler prefix. Recovers 2 STT misspellings via surname phonetic.

CREATE OR REPLACE FUNCTION public.resolve_speaker_contact(
  p_speaker_label text,
  p_project_id uuid DEFAULT NULL::uuid
)
RETURNS TABLE(
  contact_id uuid,
  contact_name text,
  is_internal boolean,
  match_quality integer,
  match_type text
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_label_lower TEXT;
  v_first_name TEXT;
  v_last_name TEXT;
BEGIN
  IF p_speaker_label IS NULL OR TRIM(p_speaker_label) = '' THEN
    RETURN;
  END IF;

  v_label_lower := LOWER(TRIM(p_speaker_label));
  v_first_name := LOWER(SPLIT_PART(p_speaker_label, ' ', 1));
  v_last_name := LOWER(SPLIT_PART(p_speaker_label, ' ', 2));

  RETURN QUERY
  WITH matches AS (
    SELECT
      c.id,
      c.name,
      (c.contact_type = 'internal') as is_internal,
      CASE
        -- Exact name match (highest)
        WHEN LOWER(c.name) = v_label_lower THEN 100
        -- Exact alias match
        WHEN EXISTS (
          SELECT 1 FROM unnest(c.aliases) AS alias
          WHERE LOWER(alias) = v_label_lower
        ) THEN 95
        -- First + last name exact match
        WHEN v_last_name != ''
          AND LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) = v_last_name THEN 90
        -- Last name exact + first name phonetic (e.g., Zack/Zachary)
        WHEN v_last_name != '' AND LENGTH(v_first_name) >= 4
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) = v_last_name
          AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name)
          THEN 80
        -- First + last both phonetic match (both names must match)
        WHEN v_last_name != '' AND LENGTH(v_first_name) >= 4 AND LENGTH(v_last_name) >= 4
          AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name)
          AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
          THEN 75
        -- Surname phonetic match with exact first name (STT misspellings)
        -- e.g., Cotrell→Cottrell, Tredaway→Treadaway
        WHEN v_last_name != '' AND LENGTH(v_last_name) >= 4
          AND LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) != v_last_name
          AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
          THEN 72
        -- First name prefix match — ONLY when no last name provided (single-token input)
        -- Downgraded from 70→65. When v_last_name is present, prefix is suppressed
        -- to prevent false matches like Dennis Sittler→Dennis Chapman.
        WHEN v_last_name = '' AND LENGTH(v_first_name) >= 4
          AND LOWER(c.name) LIKE v_first_name || '%' THEN 65
        ELSE 0
      END as match_quality,
      CASE
        WHEN LOWER(c.name) = v_label_lower THEN 'exact_name'
        WHEN EXISTS (
          SELECT 1 FROM unnest(c.aliases) AS alias
          WHERE LOWER(alias) = v_label_lower
        ) THEN 'exact_alias'
        WHEN v_last_name != ''
          AND LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) = v_last_name THEN 'exact_full_name'
        WHEN v_last_name != '' AND LENGTH(v_first_name) >= 4
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) = v_last_name
          AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name)
          THEN 'phonetic_first_exact_last'
        WHEN v_last_name != '' AND LENGTH(v_first_name) >= 4 AND LENGTH(v_last_name) >= 4
          AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name)
          AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
          THEN 'phonetic_both'
        WHEN v_last_name != '' AND LENGTH(v_last_name) >= 4
          AND LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
          AND LOWER(SPLIT_PART(c.name, ' ', 2)) != v_last_name
          AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
          THEN 'surname_phonetic'
        WHEN v_last_name = '' AND LENGTH(v_first_name) >= 4
          AND LOWER(c.name) LIKE v_first_name || '%' THEN 'first_name_prefix'
        ELSE 'none'
      END as match_type
    FROM contacts c
    WHERE
      -- Only consider contacts that could match (no substring scans)
      LOWER(c.name) = v_label_lower
      OR EXISTS (
        SELECT 1 FROM unnest(c.aliases) AS alias
        WHERE LOWER(alias) = v_label_lower
      )
      -- First+last exact components
      OR (v_last_name != ''
        AND LOWER(SPLIT_PART(c.name, ' ', 2)) = v_last_name
        AND (
          LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
          OR (LENGTH(v_first_name) >= 4 AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name))
        )
      )
      -- Both phonetic
      OR (v_last_name != '' AND LENGTH(v_first_name) >= 4 AND LENGTH(v_last_name) >= 4
        AND dmetaphone(SPLIT_PART(c.name, ' ', 1)) = dmetaphone(v_first_name)
        AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
      )
      -- Surname phonetic with exact first name
      OR (v_last_name != '' AND LENGTH(v_last_name) >= 4
        AND LOWER(SPLIT_PART(c.name, ' ', 1)) = v_first_name
        AND dmetaphone(SPLIT_PART(c.name, ' ', 2)) = dmetaphone(v_last_name)
      )
      -- First name prefix — only when no last name provided
      OR (v_last_name = '' AND LENGTH(v_first_name) >= 4 AND LOWER(c.name) LIKE v_first_name || '%')
  ),
  ranked AS (
    SELECT
      m.*,
      COALESCE(
        (SELECT cpa.weight * 10
         FROM correspondent_project_affinity cpa
         WHERE cpa.contact_id = m.id
           AND cpa.project_id = p_project_id),
        0
      ) as affinity_boost
    FROM matches m
    WHERE m.match_quality > 0
  )
  SELECT
    r.id as contact_id,
    r.name as contact_name,
    r.is_internal,
    r.match_quality,
    r.match_type
  FROM ranked r
  ORDER BY (r.match_quality + r.affinity_boost) DESC, r.is_internal DESC
  LIMIT 1;
END;
$function$;
