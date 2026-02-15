-- Deepgram transcript duplication hygiene (NULL transcript_variant).
-- Preconditions:
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
-- - coordinate with STRAT/DEV; this touches transcripts_comparison rows

BEGIN;

-- Step 1: backfill transcript_variant for deepgram NULL rows based on keywords_enabled.
UPDATE public.transcripts_comparison tc
SET transcript_variant = CASE
  WHEN tc.keywords_enabled IS TRUE THEN 'keywords_on'
  WHEN tc.keywords_enabled IS FALSE THEN 'keywords_off'
  ELSE 'keywords_on'
END
WHERE tc.engine = 'deepgram'
  AND tc.transcript_variant IS NULL;

-- Step 2: dedupe per (interaction_id, engine, transcript_variant) keeping newest by created_at.
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

