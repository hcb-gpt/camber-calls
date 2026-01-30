-- RPC: resolve_speaker_contact
-- Resolves a speaker label to a contact_id and is_internal flag
-- Used by journal_claims to populate speaker_contact_id and speaker_is_internal

CREATE OR REPLACE FUNCTION resolve_speaker_contact(
  p_speaker_label TEXT,
  p_project_id UUID DEFAULT NULL
)
RETURNS TABLE (
  contact_id UUID,
  contact_name TEXT,
  is_internal BOOLEAN,
  match_quality INT,
  match_type TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
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
        -- Alias partial match (e.g., "Ginger Landscaper" matches alias containing "Ginger")
        WHEN EXISTS (
          SELECT 1 FROM unnest(c.aliases) AS alias
          WHERE v_label_lower LIKE '%' || LOWER(alias) || '%'
             OR LOWER(alias) LIKE '%' || v_label_lower || '%'
        ) THEN 85
        -- First name + last name match (fuzzy)
        WHEN v_last_name != '' 
          AND LOWER(c.name) LIKE '%' || v_first_name || '%'
          AND LOWER(c.name) LIKE '%' || v_last_name || '%' THEN 80
        -- First name only match (name starts with first name)
        WHEN LENGTH(v_first_name) >= 3
          AND LOWER(c.name) LIKE v_first_name || '%' THEN 70
        -- First name appears in name
        WHEN LENGTH(v_first_name) >= 4
          AND LOWER(c.name) LIKE '%' || v_first_name || '%' THEN 60
        -- Last name only match
        WHEN v_last_name != '' AND LENGTH(v_last_name) >= 4
          AND LOWER(c.name) LIKE '%' || v_last_name || '%' THEN 55
        ELSE 0
      END as match_quality,
      CASE
        WHEN LOWER(c.name) = v_label_lower THEN 'exact_name'
        WHEN EXISTS (
          SELECT 1 FROM unnest(c.aliases) AS alias
          WHERE LOWER(alias) = v_label_lower
        ) THEN 'exact_alias'
        WHEN EXISTS (
          SELECT 1 FROM unnest(c.aliases) AS alias
          WHERE v_label_lower LIKE '%' || LOWER(alias) || '%'
             OR LOWER(alias) LIKE '%' || v_label_lower || '%'
        ) THEN 'partial_alias'
        WHEN v_last_name != '' 
          AND LOWER(c.name) LIKE '%' || v_first_name || '%'
          AND LOWER(c.name) LIKE '%' || v_last_name || '%' THEN 'fuzzy_full_name'
        WHEN LOWER(c.name) LIKE v_first_name || '%' THEN 'first_name_prefix'
        WHEN LOWER(c.name) LIKE '%' || v_first_name || '%' THEN 'first_name_contains'
        WHEN LOWER(c.name) LIKE '%' || v_last_name || '%' THEN 'last_name_contains'
        ELSE 'none'
      END as match_type
    FROM contacts c
    WHERE 
      -- Only consider contacts that could match
      LOWER(c.name) = v_label_lower
      OR EXISTS (
        SELECT 1 FROM unnest(c.aliases) AS alias
        WHERE LOWER(alias) = v_label_lower
           OR v_label_lower LIKE '%' || LOWER(alias) || '%'
           OR LOWER(alias) LIKE '%' || v_label_lower || '%'
      )
      OR (LENGTH(v_first_name) >= 3 AND LOWER(c.name) LIKE '%' || v_first_name || '%')
      OR (v_last_name != '' AND LENGTH(v_last_name) >= 4 AND LOWER(c.name) LIKE '%' || v_last_name || '%')
  ),
  ranked AS (
    SELECT 
      m.*,
      -- If project_id provided, boost contacts with affinity to that project
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
$$;

COMMENT ON FUNCTION resolve_speaker_contact IS 
'Resolves a speaker label from transcript to a contact_id.
Returns the best matching contact with is_internal flag.
Used to populate journal_claims.speaker_contact_id and speaker_is_internal.';;
