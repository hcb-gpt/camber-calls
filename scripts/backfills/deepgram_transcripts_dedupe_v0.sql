-- Deepgram transcript duplication hygiene (NULL transcript_variant).
-- Preconditions:
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
-- - coordinate with STRAT/DEV; this touches transcripts_comparison rows

BEGIN;

-- NOTE: transcripts_comparison has UNIQUE(interaction_id, engine, transcript_variant).
-- Multiple NULL transcript_variant rows can coexist, but updating NULL -> keywords_on/off
-- can violate the unique constraint if a typed variant row already exists.
-- So we dedupe NULL rows first, then drop would-collide rows, then backfill variant.

-- Step 1: dedupe duplicate NULL transcript_variant rows (keep newest per interaction).
WITH ranked_null AS (
  SELECT
    tc.id,
    ROW_NUMBER() OVER (
      PARTITION BY tc.interaction_id, tc.engine, tc.transcript_variant
      ORDER BY tc.created_at DESC NULLS LAST, tc.id DESC
    ) AS rn
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
    AND tc.transcript_variant IS NULL
)
DELETE FROM public.transcripts_comparison tc
USING ranked_null r
WHERE tc.id = r.id
  AND r.rn > 1;

-- Step 2: delete remaining NULL rows that would collide with an existing typed variant row.
WITH desired AS (
  SELECT
    tc.id,
    tc.interaction_id,
    CASE
      WHEN tc.keywords_enabled IS TRUE THEN 'keywords_on'
      WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
      ELSE 'keywords_on'
    END AS desired_variant
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
    AND tc.transcript_variant IS NULL
),
colliders AS (
  SELECT d.id
  FROM desired d
  JOIN public.transcripts_comparison existing
    ON existing.engine = 'deepgram'
   AND existing.interaction_id = d.interaction_id
   AND existing.transcript_variant = d.desired_variant
)
DELETE FROM public.transcripts_comparison tc
USING colliders c
WHERE tc.id = c.id;

-- Step 3: backfill transcript_variant for remaining deepgram NULL rows based on keywords_enabled.
UPDATE public.transcripts_comparison tc
SET transcript_variant = CASE
  WHEN tc.keywords_enabled IS TRUE THEN 'keywords_on'
  WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
  ELSE 'keywords_on'
END
WHERE tc.engine = 'deepgram'
  AND tc.transcript_variant IS NULL;

-- Step 4: dedupe per (interaction_id, engine, transcript_variant) keeping newest by created_at.
WITH ranked AS (
  SELECT
    tc.id,
    ROW_NUMBER() OVER (
      PARTITION BY tc.interaction_id, tc.engine, tc.transcript_variant
      ORDER BY tc.created_at DESC NULLS LAST, tc.id DESC
    ) AS rn
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
)
DELETE FROM public.transcripts_comparison tc
USING ranked r
WHERE tc.id = r.id
  AND r.rn > 1;

COMMIT;
