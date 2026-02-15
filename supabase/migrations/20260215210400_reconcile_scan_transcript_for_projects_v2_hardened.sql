-- Git reconciliation of live scan_transcript_for_projects v2
-- This migration matches the LIVE DB definition as of 2026-02-15T03:40Z
-- with the addition of SET search_path hardening (security advisory fix).
--
-- Collision history:
--   data-2 deployed v2 with plural_exact match type (overwritten)
--   data-1/data-3 deployed UNION-based depluralization variant (current live)
--   This migration captures the current live version + search_path hardening
--
-- Applied by DATA-2 session, 2026-02-15

CREATE OR REPLACE FUNCTION public.scan_transcript_for_projects(
  transcript_text text,
  similarity_threshold double precision DEFAULT 0.4,
  min_alias_length integer DEFAULT 3
)
RETURNS TABLE(
  project_id uuid,
  project_name text,
  matched_term text,
  matched_alias text,
  match_type text,
  score double precision
)
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_transcript_lower TEXT;
BEGIN
  v_transcript_lower := LOWER(transcript_text);
  RETURN QUERY
  WITH alias_candidates AS (
    SELECT pa.project_id AS ac_project_id, p.name AS ac_project_name,
      pa.alias AS ac_alias, pa.alias_type AS ac_alias_type,
      pa.confidence AS ac_confidence, LOWER(pa.alias) AS ac_alias_lower,
      (pa.alias_type = 'client_last_name' AND LENGTH(pa.alias) <= 5) AS ac_is_common
    FROM project_aliases pa
    JOIN projects p ON pa.project_id = p.id
    WHERE LENGTH(pa.alias) >= min_alias_length
      AND p.status IN ('active', 'warranty', 'pre-construction')
  ),
  -- Extract words from transcript, then generate depluralized variants
  raw_words AS (
    SELECT LOWER(m[1]) AS rw_word
    FROM regexp_matches(transcript_text, '([a-zA-Z][a-zA-Z'']+)', 'g') AS m
    WHERE LENGTH(m[1]) >= min_alias_length
  ),
  transcript_words AS (
    -- Original word
    SELECT rw_word AS tw_word, rw_word AS tw_original, 'original'::TEXT AS tw_variant_type,
      strpos(v_transcript_lower, rw_word) AS tw_start
    FROM raw_words
    UNION
    -- Depluralized: strip possessive 's  (e.g., "skelton's" -> "skelton")
    SELECT regexp_replace(rw_word, '''s$', '') AS tw_word, rw_word AS tw_original,
      'possessive_stripped'::TEXT AS tw_variant_type,
      strpos(v_transcript_lower, rw_word) AS tw_start
    FROM raw_words
    WHERE rw_word ~ '''s$'
      AND LENGTH(regexp_replace(rw_word, '''s$', '')) >= min_alias_length
    UNION
    -- Depluralized: strip trailing "es" for words ending in "ses","xes","zes","shes","ches"
    -- e.g., "mosses" -> "moss", "foxes" -> "fox"
    SELECT regexp_replace(rw_word, '(ss|x|z|sh|ch)es$', '\1') AS tw_word,
      rw_word AS tw_original, 'deplural_es'::TEXT AS tw_variant_type,
      strpos(v_transcript_lower, rw_word) AS tw_start
    FROM raw_words
    WHERE rw_word ~ '(ss|x|z|sh|ch)es$'
      AND LENGTH(regexp_replace(rw_word, '(ss|x|z|sh|ch)es$', '\1')) >= min_alias_length
    UNION
    -- Depluralized: strip trailing "ies" -> "y" (e.g., "hurries" -> "hurry")
    SELECT regexp_replace(rw_word, 'ies$', 'y') AS tw_word,
      rw_word AS tw_original, 'deplural_ies'::TEXT AS tw_variant_type,
      strpos(v_transcript_lower, rw_word) AS tw_start
    FROM raw_words
    WHERE rw_word ~ 'ies$'
      AND LENGTH(regexp_replace(rw_word, 'ies$', 'y')) >= min_alias_length
    UNION
    -- Depluralized: strip simple trailing "s" (e.g., "skeletons" -> "skeleton", "hurleys" -> "hurley")
    SELECT regexp_replace(rw_word, 's$', '') AS tw_word,
      rw_word AS tw_original, 'deplural_s'::TEXT AS tw_variant_type,
      strpos(v_transcript_lower, rw_word) AS tw_start
    FROM raw_words
    WHERE rw_word ~ '[^s]s$'  -- ends in s but not ss (handled above)
      AND rw_word !~ '''s$'   -- not possessive (handled above)
      AND rw_word !~ 'ies$'   -- not ies plural (handled above)
      AND LENGTH(regexp_replace(rw_word, 's$', '')) >= min_alias_length
  ),
  exact_matches AS (
    SELECT ac.ac_project_id, ac.ac_project_name,
      ac.ac_alias AS em_matched_term, ac.ac_alias AS em_matched_alias,
      'exact'::TEXT AS em_match_type, 1.0::DOUBLE PRECISION AS em_score,
      ac.ac_is_common, ac.ac_alias_lower
    FROM alias_candidates ac
    WHERE v_transcript_lower ~ ('\y' || ac.ac_alias_lower || '\y')
  ),
  fuzzy_single AS (
    SELECT ac.ac_project_id, ac.ac_project_name,
      tw.tw_original AS em_matched_term, ac.ac_alias AS em_matched_alias,
      CASE WHEN tw.tw_variant_type = 'original' THEN 'fuzzy'
           ELSE 'fuzzy_deplural' END::TEXT AS em_match_type,
      (CASE WHEN tw.tw_variant_type = 'original' THEN 1.0 ELSE 0.95 END
        * (0.5 + (similarity(tw.tw_word, ac.ac_alias_lower) - similarity_threshold) * (0.4 / 0.7))
      )::DOUBLE PRECISION AS em_score,
      ac.ac_is_common, ac.ac_alias_lower, tw.tw_start
    FROM transcript_words tw CROSS JOIN alias_candidates ac
    WHERE ac.ac_alias_lower !~ '\s'
      AND LENGTH(ac.ac_alias_lower) >= 5 AND LENGTH(tw.tw_word) >= 5
      AND similarity(tw.tw_word, ac.ac_alias_lower) >= similarity_threshold
      AND tw.tw_word <> ac.ac_alias_lower
  ),
  fuzzy_multi AS (
    SELECT ac.ac_project_id, ac.ac_project_name,
      ac.ac_alias AS em_matched_term, ac.ac_alias AS em_matched_alias,
      'fuzzy'::TEXT AS em_match_type,
      (0.5 + (word_similarity(ac.ac_alias_lower, v_transcript_lower) - similarity_threshold) * (0.4 / 0.7))::DOUBLE PRECISION AS em_score,
      ac.ac_is_common, ac.ac_alias_lower, 0 AS tw_start
    FROM alias_candidates ac
    WHERE ac.ac_alias_lower ~ '\s'
      AND word_similarity(ac.ac_alias_lower, v_transcript_lower) >= 0.5
      AND NOT (v_transcript_lower ~ ('\y' || ac.ac_alias_lower || '\y'))
  ),
  phonetic AS (
    SELECT ac.ac_project_id, ac.ac_project_name,
      tw.tw_original AS em_matched_term, ac.ac_alias AS em_matched_alias,
      CASE WHEN tw.tw_variant_type = 'original' THEN 'phonetic'
           ELSE 'phonetic_deplural' END::TEXT AS em_match_type,
      (CASE WHEN tw.tw_variant_type = 'original' THEN 1.0 ELSE 0.95 END
        * GREATEST(0.4, 0.7 - (levenshtein(tw.tw_word, ac.ac_alias_lower)::DOUBLE PRECISION * 0.075))
      )::DOUBLE PRECISION AS em_score,
      ac.ac_is_common, ac.ac_alias_lower, tw.tw_start
    FROM transcript_words tw CROSS JOIN alias_candidates ac
    WHERE ac.ac_alias_lower !~ '\s'
      AND LENGTH(ac.ac_alias_lower) >= 6 AND LENGTH(tw.tw_word) >= 6
      AND tw.tw_word <> ac.ac_alias_lower
      AND similarity(tw.tw_word, ac.ac_alias_lower) < similarity_threshold
      AND (soundex(tw.tw_word) = soundex(ac.ac_alias_lower)
        OR dmetaphone(tw.tw_word) = dmetaphone(ac.ac_alias_lower))
  ),
  all_matches AS (
    SELECT ac_project_id, ac_project_name, em_matched_term, em_matched_alias,
      em_match_type, em_score, ac_is_common, ac_alias_lower,
      strpos(v_transcript_lower, ac_alias_lower) AS am_pos
    FROM exact_matches
    UNION ALL
    SELECT ac_project_id, ac_project_name, em_matched_term, em_matched_alias,
      em_match_type, em_score, ac_is_common, ac_alias_lower, tw_start AS am_pos
    FROM fuzzy_single
    UNION ALL
    SELECT ac_project_id, ac_project_name, em_matched_term, em_matched_alias,
      em_match_type, em_score, ac_is_common, ac_alias_lower,
      GREATEST(1, strpos(v_transcript_lower, ac_alias_lower)) AS am_pos
    FROM fuzzy_multi
    UNION ALL
    SELECT ac_project_id, ac_project_name, em_matched_term, em_matched_alias,
      em_match_type, em_score, ac_is_common, ac_alias_lower, tw_start AS am_pos
    FROM phonetic
  ),
  guarded AS (
    SELECT am.ac_project_id, am.ac_project_name, am.em_matched_term,
      am.em_matched_alias, am.em_match_type, am.em_score
    FROM all_matches am
    WHERE NOT am.ac_is_common
      OR (am.ac_is_common AND EXISTS (
        SELECT 1 WHERE
          v_transcript_lower ~ ('\y' || am.ac_alias_lower || '''s')
          OR (substring(v_transcript_lower
            FROM GREATEST(1, am.am_pos - 50)
            FOR LENGTH(am.em_matched_term) + 100
          ) ~ '\y(residence|house|project|job|place|property|build|remodel|renovation|bathroom|kitchen)\y')
      ))
  ),
  ranked AS (
    SELECT g.ac_project_id, g.ac_project_name, g.em_matched_term,
      g.em_matched_alias, g.em_match_type, g.em_score,
      ROW_NUMBER() OVER (
        PARTITION BY g.ac_project_id, g.em_matched_alias
        ORDER BY g.em_score DESC,
          CASE g.em_match_type
            WHEN 'exact' THEN 1
            WHEN 'fuzzy' THEN 2
            WHEN 'fuzzy_deplural' THEN 3
            WHEN 'phonetic' THEN 4
            WHEN 'phonetic_deplural' THEN 5
          END
      ) AS rn
    FROM guarded g
  )
  SELECT r.ac_project_id, r.ac_project_name, r.em_matched_term,
    r.em_matched_alias, r.em_match_type, r.em_score
  FROM ranked r WHERE r.rn = 1
  ORDER BY r.em_score DESC, r.ac_project_name, r.em_matched_alias;
END;
$function$;
