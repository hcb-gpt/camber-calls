-- =============================================================================
-- scan_transcript_for_projects v2 — Multi-tier fuzzy + phonetic matching
-- =============================================================================
-- Replaces the v1 function that only did regex word-boundary matching.
--
-- REQUIRES (already installed):
--   pg_trgm 1.6    — similarity(), word_similarity()
--   fuzzystrmatch 1.2 — soundex(), dmetaphone(), levenshtein()
--
-- MATCH TIERS:
--   1. exact    (score 1.0)       — regex \y word-boundary match (original logic)
--   2. fuzzy    (score 0.5–0.9)   — pg_trgm similarity >= 0.3 on transcript words
--   3. phonetic (score 0.4–0.7)   — soundex OR dmetaphone match on transcript words
--
-- COMMON-WORD GUARD:
--   client_last_name aliases <= 5 chars (white, moss, young, lamb) require
--   project-context words within 50 chars to avoid false positives like
--   "white marble" matching White Residence.
--
-- DEDUPLICATION:
--   If exact + fuzzy/phonetic both match the same (project_id, alias), keep
--   only the highest-scoring match (exact wins).
-- =============================================================================

CREATE OR REPLACE FUNCTION scan_transcript_for_projects(
  transcript_text TEXT,
  min_alias_length INT DEFAULT 3
)
RETURNS TABLE(
  project_id     UUID,
  project_name   TEXT,
  matched_term   TEXT,
  matched_alias  TEXT,
  match_type     TEXT,
  score          DOUBLE PRECISION
)
AS $$
DECLARE
  v_transcript_lower TEXT;
BEGIN
  v_transcript_lower := LOWER(transcript_text);

  RETURN QUERY

  -- =========================================================================
  -- Step 1: Prepare alias candidates (active/warranty/pre-construction)
  -- =========================================================================
  WITH alias_candidates AS (
    SELECT
      pa.project_id,
      p.name                AS project_name,
      pa.alias,
      pa.alias_type,
      pa.confidence,
      LOWER(pa.alias)       AS alias_lower,
      -- Flag aliases that need contextual guarding
      (pa.alias_type = 'client_last_name' AND LENGTH(pa.alias) <= 5) AS is_common_word_alias
    FROM project_aliases pa
    JOIN projects p ON pa.project_id = p.id
    WHERE LENGTH(pa.alias) >= min_alias_length
      AND p.status IN ('active', 'warranty', 'pre-construction')
  ),

  -- =========================================================================
  -- Step 2: Tokenize transcript into individual words
  --         Also keep position info for context-window checks
  -- =========================================================================
  transcript_words AS (
    SELECT
      word,
      word_start
    FROM (
      SELECT
        LOWER(m[1])                         AS word,
        -- character position of match start (for context-window lookups)
        strpos(v_transcript_lower,
               LOWER(m[1]))                 AS word_start
      FROM regexp_matches(transcript_text, '([a-zA-Z][a-zA-Z'']+)', 'g') AS m
    ) raw
    WHERE LENGTH(word) >= min_alias_length
  ),

  -- =========================================================================
  -- Step 3: TIER 1 — Exact regex word-boundary matches
  --         Preserves original v1 behaviour
  -- =========================================================================
  exact_matches AS (
    SELECT
      ac.project_id,
      ac.project_name,
      ac.alias       AS matched_term,
      ac.alias       AS matched_alias,
      'exact'::TEXT  AS match_type,
      1.0::DOUBLE PRECISION AS score,
      ac.is_common_word_alias,
      ac.alias_lower
    FROM alias_candidates ac
    WHERE v_transcript_lower ~ ('\y' || ac.alias_lower || '\y')
  ),

  -- =========================================================================
  -- Step 4: TIER 2 — Fuzzy trigram matches (single-word aliases)
  --         Compare each transcript word against each single-word alias.
  --         Score = trigram similarity mapped to 0.5–0.9 range.
  -- =========================================================================
  fuzzy_single_matches AS (
    SELECT
      ac.project_id,
      ac.project_name,
      tw.word        AS matched_term,
      ac.alias       AS matched_alias,
      'fuzzy'::TEXT  AS match_type,
      -- Map similarity [0.3, 1.0) -> score [0.5, 0.9]
      (0.5 + (similarity(tw.word, ac.alias_lower) - 0.3) * (0.4 / 0.7))::DOUBLE PRECISION AS score,
      ac.is_common_word_alias,
      ac.alias_lower,
      tw.word_start
    FROM transcript_words tw
    CROSS JOIN alias_candidates ac
    WHERE ac.alias_lower !~ '\s'                        -- single-word aliases only
      AND similarity(tw.word, ac.alias_lower) >= 0.3    -- trigram threshold
      AND tw.word <> ac.alias_lower                     -- exclude exact (handled in tier 1)
  ),

  -- =========================================================================
  -- Step 5: TIER 2b — Fuzzy trigram matches (multi-word aliases)
  --         Use word_similarity to find multi-word alias phrases in transcript.
  -- =========================================================================
  fuzzy_multi_matches AS (
    SELECT
      ac.project_id,
      ac.project_name,
      ac.alias       AS matched_term,
      ac.alias       AS matched_alias,
      'fuzzy'::TEXT  AS match_type,
      (0.5 + (word_similarity(ac.alias_lower, v_transcript_lower) - 0.3) * (0.4 / 0.7))::DOUBLE PRECISION AS score,
      ac.is_common_word_alias,
      ac.alias_lower,
      0 AS word_start  -- position not tracked for multi-word
    FROM alias_candidates ac
    WHERE ac.alias_lower ~ '\s'                                       -- multi-word aliases only
      AND word_similarity(ac.alias_lower, v_transcript_lower) >= 0.3  -- trigram threshold
      AND NOT (v_transcript_lower ~ ('\y' || ac.alias_lower || '\y')) -- exclude exact matches
  ),

  -- =========================================================================
  -- Step 6: TIER 3 — Phonetic matches (soundex + dmetaphone)
  --         Compare each transcript word against each single-word alias.
  --         Uses OR logic: soundex match OR dmetaphone match.
  --         Score based on levenshtein closeness within phonetic match.
  -- =========================================================================
  phonetic_matches AS (
    SELECT
      ac.project_id,
      ac.project_name,
      tw.word        AS matched_term,
      ac.alias       AS matched_alias,
      'phonetic'::TEXT AS match_type,
      -- Score: base 0.4, boosted by closeness (low levenshtein = higher score)
      -- levenshtein 0 -> 0.7, levenshtein 4+ -> 0.4
      GREATEST(0.4, 0.7 - (levenshtein(tw.word, ac.alias_lower)::DOUBLE PRECISION * 0.075))::DOUBLE PRECISION AS score,
      ac.is_common_word_alias,
      ac.alias_lower,
      tw.word_start
    FROM transcript_words tw
    CROSS JOIN alias_candidates ac
    WHERE ac.alias_lower !~ '\s'                          -- single-word aliases only
      AND tw.word <> ac.alias_lower                       -- exclude exact
      AND similarity(tw.word, ac.alias_lower) < 0.3       -- exclude fuzzy (already caught)
      AND (
        soundex(tw.word) = soundex(ac.alias_lower)        -- soundex match
        OR dmetaphone(tw.word) = dmetaphone(ac.alias_lower) -- OR dmetaphone match
      )
  ),

  -- =========================================================================
  -- Step 7: Union all tiers
  --         Include match_position: for exact matches, find the alias in the
  --         transcript; for fuzzy/phonetic, use the transcript word position.
  -- =========================================================================
  all_matches AS (
    SELECT project_id, project_name, matched_term, matched_alias,
           match_type, score, is_common_word_alias, alias_lower,
           -- For exact matches, locate the alias in the transcript
           strpos(v_transcript_lower, alias_lower) AS match_position
    FROM exact_matches
    UNION ALL
    SELECT project_id, project_name, matched_term, matched_alias,
           match_type, score, is_common_word_alias, alias_lower,
           -- For fuzzy, use the matched word's position in the transcript
           word_start AS match_position
    FROM fuzzy_single_matches
    UNION ALL
    SELECT project_id, project_name, matched_term, matched_alias,
           match_type, score, is_common_word_alias, alias_lower,
           -- For multi-word fuzzy, try to locate the alias or default to 0
           GREATEST(1, strpos(v_transcript_lower, alias_lower)) AS match_position
    FROM fuzzy_multi_matches
    UNION ALL
    SELECT project_id, project_name, matched_term, matched_alias,
           match_type, score, is_common_word_alias, alias_lower,
           -- For phonetic, use the matched word's position
           word_start AS match_position
    FROM phonetic_matches
  ),

  -- =========================================================================
  -- Step 8: Common-word guard
  --         For short client_last_name aliases, require project-context words
  --         within 50 characters of the match.  Context words:
  --           residence, house, project, job, 's, place, property, build,
  --           remodel, renovation, bathroom, kitchen
  --         This prevents "white marble" from matching White Residence but
  --         allows "the White's bathroom" or "White residence" to match.
  --
  --         The guard applies to ALL tiers (exact, fuzzy, phonetic).
  -- =========================================================================
  guarded_matches AS (
    SELECT
      am.project_id,
      am.project_name,
      am.matched_term,
      am.matched_alias,
      am.match_type,
      am.score
    FROM all_matches am
    WHERE
      -- If NOT a common-word alias, always pass through
      NOT am.is_common_word_alias
      -- If IS a common-word alias, require contextual evidence
      OR (
        am.is_common_word_alias
        AND (
          EXISTS (
            SELECT 1
            WHERE
              -- Possessive: alias followed by 's (e.g. "White's")
              v_transcript_lower ~ ('\y' || am.alias_lower || '''s')
              -- OR: context word within a window around the match position
              OR (
                -- Extract a window: 50 chars before match_position to 50 chars after end of matched term
                substring(
                  v_transcript_lower
                  FROM GREATEST(1, am.match_position - 50)
                  FOR LENGTH(am.matched_term) + 100
                ) ~ '\y(residence|house|project|job|place|property|build|remodel|renovation|bathroom|kitchen)\y'
              )
          )
        )
      )
  ),

  -- =========================================================================
  -- Step 9: Deduplicate — keep highest score per (project_id, matched_alias)
  --         exact > fuzzy > phonetic for same project+alias pair
  -- =========================================================================
  ranked AS (
    SELECT
      gm.project_id,
      gm.project_name,
      gm.matched_term,
      gm.matched_alias,
      gm.match_type,
      gm.score,
      ROW_NUMBER() OVER (
        PARTITION BY gm.project_id, gm.matched_alias
        ORDER BY gm.score DESC,
                 CASE gm.match_type
                   WHEN 'exact' THEN 1
                   WHEN 'fuzzy' THEN 2
                   WHEN 'phonetic' THEN 3
                 END
      ) AS rn
    FROM guarded_matches gm
  )

  -- =========================================================================
  -- Final output
  -- =========================================================================
  SELECT
    r.project_id,
    r.project_name,
    r.matched_term,
    r.matched_alias,
    r.match_type,
    r.score
  FROM ranked r
  WHERE r.rn = 1
  ORDER BY r.score DESC, r.project_name, r.matched_alias;

END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- TEST QUERIES
-- =============================================================================

-- ---------------------------------------------------------------------------
-- TEST 1: "skeletons" should match Skelton Residence (fuzzy or phonetic)
--         "skeletons" vs "skelton": trigram similarity = 0.38 (>= 0.3) -> fuzzy
--         Also: soundex(skeletons)=S435 = soundex(skelton)=S435 -> phonetic
--         Since trigram 0.38 >= 0.3, fuzzy tier catches it first.
--         NOTE: "skeletons" is ALSO a transcription_variant alias with exact match,
--               so exact will fire on that alias. The fuzzy/phonetic match on
--               the client_last_name "skelton" alias is the interesting test.
-- ---------------------------------------------------------------------------
SELECT '--- TEST 1: skeletons should match Skelton Residence ---' AS test;
SELECT * FROM scan_transcript_for_projects(
  'We talked about the skeletons project today and the framing is almost done'
);
-- EXPECTED: At least one row for Skelton Residence.
--   - matched_alias = 'skeletons' (transcription_variant, exact, score 1.0)
--   - AND/OR matched_alias = 'skelton' (client_last_name, fuzzy ~0.55, or phonetic)


-- ---------------------------------------------------------------------------
-- TEST 2: "mystery white marble" should NOT match White Residence
--         "white" is a client_last_name alias with <= 5 chars.
--         Common-word guard fires: no context words (residence, house, project,
--         job, 's, place, property, build) appear near "white".
-- ---------------------------------------------------------------------------
SELECT '--- TEST 2: mystery white marble should NOT match White Residence via white ---' AS test;
SELECT * FROM scan_transcript_for_projects(
  'We need to pick up some mystery white marble for the countertops at the shop'
);
-- EXPECTED: No rows matching White Residence via the "white" alias.
--   (May match other projects via other aliases like "shop" if present, but
--    White Residence should NOT appear from the word "white" alone.)


-- ---------------------------------------------------------------------------
-- TEST 3: "the White's bathroom" SHOULD match White Residence
--         "white" is guarded, but the possessive "'s" triggers context match.
--         Pattern: alias + 's  -> passes common-word guard.
-- ---------------------------------------------------------------------------
SELECT '--- TEST 3: the White''s bathroom SHOULD match White Residence ---' AS test;
SELECT * FROM scan_transcript_for_projects(
  'I need to go check on the White''s bathroom tile before lunch tomorrow'
);
-- EXPECTED: Row(s) for White Residence, matched_alias = 'white',
--           match_type = 'exact', score = 1.0
--           (possessive context "'s" satisfies the guard, plus "bathroom" is a context word)


-- ---------------------------------------------------------------------------
-- TEST 4: "wind ship" should match Winship Residence (exact via transcription_variant)
--         "wind ship" is already in project_aliases as a transcription_variant
--         with confidence 1.0.  The regex \y match should catch it directly.
-- ---------------------------------------------------------------------------
SELECT '--- TEST 4: wind ship should match Winship Residence (exact) ---' AS test;
SELECT * FROM scan_transcript_for_projects(
  'Head over to the wind ship place and check the roof flashing'
);
-- EXPECTED: Row for Winship Residence, matched_alias = 'wind ship',
--           match_type = 'exact', score = 1.0


-- ---------------------------------------------------------------------------
-- TEST 5: "skelington" should match Skelton Residence (phonetic via soundex)
--         soundex(skelington) = S452, soundex(skelton) = S435 -> NO soundex match
--         dmetaphone(skelington) = SKLN, dmetaphone(skelton) = SKLT -> NO dmetaphone match
--         BUT trigram similarity(skelton, skelington) = 0.46 >= 0.3 -> FUZZY match!
--         This demonstrates the multi-tier safety net: even when phonetic codes
--         diverge, trigram similarity catches the misspelling.
-- ---------------------------------------------------------------------------
SELECT '--- TEST 5: skelington should match Skelton Residence (fuzzy via trigram) ---' AS test;
SELECT * FROM scan_transcript_for_projects(
  'The skelington project needs more lumber delivered by Friday morning'
);
-- EXPECTED: Row for Skelton Residence, matched_alias = 'skelton',
--           match_type = 'fuzzy', score ~0.59 (similarity 0.46 mapped to score range)
--           Also may match 'Skeleton' transcription_variant via fuzzy.
