-- Deepgram transcript duplication hygiene (historically NULL/blank transcript_variant).
-- Preconditions:
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
-- - coordinate with STRAT/DEV; this touches transcripts_comparison rows

BEGIN;

-- IMPORTANT:
-- We must delete dupes BEFORE normalizing transcript_variant, otherwise mass-updating
-- multiple NULL/blank rows to the same value violates the unique constraint:
--   UNIQUE (interaction_id, engine, transcript_variant)

-- Step 1: compute a normalized target_variant, then delete all but newest row per
-- (interaction_id, engine, target_variant).
WITH dg AS (
  SELECT
    tc.id,
    tc.interaction_id,
    tc.engine,
    tc.created_at,
    tc.keywords_enabled,
    NULLIF(btrim(tc.transcript_variant), '') AS transcript_variant_clean,
    CASE
      WHEN NULLIF(btrim(tc.transcript_variant), '') IN ('keywords_on', 'post') THEN 'keywords_on'
      WHEN NULLIF(btrim(tc.transcript_variant), '') IN ('keywords_off', 'pre') THEN 'keywords_off'
      WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
      ELSE 'keywords_on'
    END AS target_variant
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
),
ranked AS (
  SELECT
    dg.id,
    ROW_NUMBER() OVER (
      PARTITION BY dg.interaction_id, dg.engine, dg.target_variant
      ORDER BY dg.created_at DESC NULLS LAST, dg.id DESC
    ) AS rn
  FROM dg
),
to_delete AS (
  SELECT id FROM ranked WHERE rn > 1
),
deleted AS (
  DELETE FROM public.transcripts_comparison tc
  USING to_delete d
  WHERE tc.id = d.id
  RETURNING 1
)
SELECT COUNT(*) AS deleted_rows FROM deleted;

-- Step 2: normalize transcript_variant on remaining rows (now uniqueness-safe).
WITH keep AS (
  SELECT
    tc.id,
    NULLIF(btrim(tc.transcript_variant), '') AS transcript_variant_clean,
    tc.keywords_enabled,
    CASE
      WHEN NULLIF(btrim(tc.transcript_variant), '') IN ('keywords_on', 'post') THEN 'keywords_on'
      WHEN NULLIF(btrim(tc.transcript_variant), '') IN ('keywords_off', 'pre') THEN 'keywords_off'
      WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
      ELSE 'keywords_on'
    END AS target_variant
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
)
UPDATE public.transcripts_comparison tc
SET transcript_variant = k.target_variant
FROM keep k
WHERE tc.id = k.id
  AND (
    k.transcript_variant_clean IS NULL
    OR k.transcript_variant_clean IN ('pre', 'post')
    OR k.transcript_variant_clean NOT IN ('keywords_on', 'keywords_off')
  );

-- Sanity check: no NULL/blank variants remain.
SELECT
  COUNT(*) FILTER (WHERE transcript_variant IS NULL OR btrim(transcript_variant) = '') AS null_or_blank_variant_rows,
  COUNT(*) AS deepgram_rows
FROM public.transcripts_comparison
WHERE engine = 'deepgram';

COMMIT;
