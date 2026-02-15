-- Deepgram transcript duplication hygiene (NULL transcript_variant).
-- Preconditions:
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
-- - coordinate with STRAT/DEV; this touches transcripts_comparison rows

BEGIN;

-- Step 1: dedupe by *desired* variant first.
-- Why: transcript_variant=NULL bypasses the uniqueness constraint; once backfilled,
-- duplicates can violate (interaction_id, engine, transcript_variant).
WITH desired AS (
  SELECT
    tc.id,
    tc.interaction_id,
    tc.engine,
    COALESCE(
      tc.transcript_variant,
      CASE
        WHEN tc.keywords_enabled IS TRUE THEN 'keywords_on'
        WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
        ELSE 'keywords_on'
      END
    ) AS desired_variant,
    tc.created_at
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
),
ranked AS (
  SELECT
    d.id,
    ROW_NUMBER() OVER (
      PARTITION BY d.interaction_id, d.engine, d.desired_variant
      ORDER BY d.created_at DESC NULLS LAST, d.id DESC
    ) AS rn
  FROM desired d
)
DELETE FROM public.transcripts_comparison tc
USING ranked r
WHERE tc.id = r.id
  AND r.rn > 1;

-- Step 2: backfill transcript_variant for remaining deepgram NULL rows.
UPDATE public.transcripts_comparison tc
SET transcript_variant = CASE
  WHEN tc.keywords_enabled IS TRUE THEN 'keywords_on'
  WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
  ELSE 'keywords_on'
END
WHERE tc.engine = 'deepgram'
  AND tc.transcript_variant IS NULL;

COMMIT;
