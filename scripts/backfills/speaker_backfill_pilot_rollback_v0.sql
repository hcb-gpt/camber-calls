-- Rollback for speaker_backfill_pilot_apply_v0.sql.
-- Edit the timestamp window to match your pilot run.
-- Run with psql directly (do not use scripts/query.sh; this file mutates data)

BEGIN;

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

COMMIT;

