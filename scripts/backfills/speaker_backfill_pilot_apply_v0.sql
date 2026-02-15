-- Pilot apply for diarized speaker resolution (Deepgram SPEAKER_N).
-- Preconditions:
-- - migrations applied: 20260215224500_deepgram_speaker_resolution_v2.sql (function + audit table + trigger updates)
-- - run with psql directly (do not use scripts/query.sh; this file mutates data)
--
-- Safety:
-- - runs in a transaction
-- - limits to a small call set (edit LIMIT in pilot_calls)
-- - writes a row-per-claim audit entry to speaker_resolution_audit

BEGIN;

WITH resolved AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.claim_id,
    jc.call_id,
    jc.project_id,
    jc.speaker_label,
    jc.speaker_contact_id AS old_speaker_contact_id,
    r.contact_id AS new_speaker_contact_id,
    r.is_internal AS new_speaker_is_internal,
    r.match_quality,
    r.match_type
  FROM public.journal_claims jc
  JOIN LATERAL public.resolve_speaker_contact_v2(jc.speaker_label, jc.project_id, jc.call_id) r ON TRUE
  WHERE jc.speaker_label ~ '^SPEAKER_[0-9]+$'
    AND jc.speaker_contact_id IS NULL
    AND r.contact_id IS NOT NULL
),
pilot_calls AS (
  SELECT DISTINCT call_id
  FROM resolved
  ORDER BY call_id ASC
  LIMIT 5
),
pilot AS (
  SELECT r.*
  FROM resolved r
  JOIN pilot_calls pc USING (call_id)
)
INSERT INTO public.speaker_resolution_audit (
  journal_claim_row_id,
  claim_id,
  call_id,
  project_id,
  speaker_label,
  old_speaker_contact_id,
  new_speaker_contact_id,
  new_speaker_is_internal,
  match_quality,
  match_type
)
SELECT
  p.journal_claim_row_id,
  p.claim_id,
  p.call_id,
  p.project_id,
  p.speaker_label,
  p.old_speaker_contact_id,
  p.new_speaker_contact_id,
  p.new_speaker_is_internal,
  p.match_quality,
  p.match_type
FROM pilot p;

WITH pilot AS (
  SELECT
    jc.id AS journal_claim_row_id,
    r.contact_id AS new_speaker_contact_id,
    r.is_internal AS new_speaker_is_internal
  FROM public.journal_claims jc
  JOIN LATERAL public.resolve_speaker_contact_v2(jc.speaker_label, jc.project_id, jc.call_id) r ON TRUE
  WHERE jc.speaker_label ~ '^SPEAKER_[0-9]+$'
    AND jc.speaker_contact_id IS NULL
    AND r.contact_id IS NOT NULL
    AND jc.call_id IN (
      SELECT DISTINCT call_id
      FROM public.speaker_resolution_audit
      WHERE applied_at >= now() - interval '10 minutes'
    )
)
UPDATE public.journal_claims jc
SET
  speaker_contact_id = p.new_speaker_contact_id,
  speaker_is_internal = p.new_speaker_is_internal
FROM pilot p
WHERE jc.id = p.journal_claim_row_id;

SELECT
  COUNT(*) AS audit_rows_written_last_10m,
  COUNT(DISTINCT call_id) AS calls_touched_last_10m
FROM public.speaker_resolution_audit
WHERE applied_at >= now() - interval '10 minutes';

COMMIT;

