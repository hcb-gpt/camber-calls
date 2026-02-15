-- Rollback for speaker_backfill_pilot_apply_v0.sql.
-- Edit the timestamp window to match your pilot run.
-- Run with psql directly (do not use scripts/query.sh; this file mutates data)

BEGIN;

-- IMPORTANT:
-- Rollback must temporarily disable the journal_claims speaker auto-resolution
-- trigger; otherwise any rows restored to NULL will be immediately re-resolved.
-- The DISABLE/ENABLE is transactional (safe if the transaction aborts).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_resolve_journal_claim_speakers'
      AND tgrelid = 'public.journal_claims'::regclass
  ) THEN
    EXECUTE 'ALTER TABLE public.journal_claims DISABLE TRIGGER trg_resolve_journal_claim_speakers';
  END IF;
END
$$;

WITH target AS (
  SELECT *
  FROM public.speaker_resolution_audit
  WHERE match_type LIKE 'deepgram_%'
    AND applied_at >= (now() - interval '60 minutes')
)
UPDATE public.journal_claims jc
SET
  speaker_contact_id = t.old_speaker_contact_id,
  speaker_is_internal = NULL
FROM target t
WHERE jc.id = t.journal_claim_row_id;

DELETE FROM public.speaker_resolution_audit a
WHERE a.id IN (SELECT id FROM target);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_resolve_journal_claim_speakers'
      AND tgrelid = 'public.journal_claims'::regclass
  ) THEN
    EXECUTE 'ALTER TABLE public.journal_claims ENABLE TRIGGER trg_resolve_journal_claim_speakers';
  END IF;
END
$$;

COMMIT;
