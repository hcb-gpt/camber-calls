-- Backfill: resolve Deepgram diarization speaker labels (SPEAKER_N) to contacts
-- Requires: migration 20260215224500_deepgram_speaker_resolution_v2.sql applied
-- Safety: Run dry-run section first; CHAD gate before applying writes.

-- ---------------------------------------------------------------------------
-- 0) DRY RUN SUMMARY
-- ---------------------------------------------------------------------------
WITH targets AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.claim_id,
    jc.call_id,
    COALESCE(jc.claim_project_id, jc.project_id) AS project_id,
    jc.speaker_label,
    jc.speaker_contact_id AS old_speaker_contact_id
  FROM public.journal_claims jc
  WHERE jc.speaker_contact_id IS NULL
    AND jc.speaker_label ILIKE 'SPEAKER\_%'
),
resolved AS (
  SELECT
    t.*,
    r.contact_id AS new_speaker_contact_id,
    r.is_internal AS new_speaker_is_internal,
    r.match_quality,
    r.match_type
  FROM targets t
  LEFT JOIN LATERAL public.resolve_speaker_contact_v2(t.speaker_label, t.project_id, t.call_id) r ON true
)
SELECT
  COUNT(*) AS target_claims,
  COUNT(*) FILTER (WHERE new_speaker_contact_id IS NOT NULL) AS resolvable_claims,
  ROUND(100.0 * COUNT(*) FILTER (WHERE new_speaker_contact_id IS NOT NULL) / NULLIF(COUNT(*), 0), 1) AS resolvable_pct
FROM resolved;

-- ---------------------------------------------------------------------------
-- 1) OPTIONAL: SAMPLE CHECK (first 50 resolvable)
-- ---------------------------------------------------------------------------
WITH targets AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.claim_id,
    jc.call_id,
    COALESCE(jc.claim_project_id, jc.project_id) AS project_id,
    jc.speaker_label,
    jc.claim_text
  FROM public.journal_claims jc
  WHERE jc.speaker_contact_id IS NULL
    AND jc.speaker_label ILIKE 'SPEAKER\_%'
),
resolved AS (
  SELECT
    t.*,
    r.contact_id,
    r.contact_name,
    r.is_internal,
    r.match_quality,
    r.match_type
  FROM targets t
  LEFT JOIN LATERAL public.resolve_speaker_contact_v2(t.speaker_label, t.project_id, t.call_id) r ON true
  WHERE r.contact_id IS NOT NULL
)
SELECT *
FROM resolved
ORDER BY match_quality DESC, match_type
LIMIT 50;

-- ---------------------------------------------------------------------------
-- 2) APPLY BACKFILL (WRITE) + AUDIT
-- ---------------------------------------------------------------------------
-- CHAD GATE: Do not run without explicit approval.
-- BEGIN;
-- WITH targets AS (
--   SELECT
--     jc.id AS journal_claim_row_id,
--     jc.claim_id,
--     jc.call_id,
--     COALESCE(jc.claim_project_id, jc.project_id) AS project_id,
--     jc.speaker_label,
--     jc.speaker_contact_id AS old_speaker_contact_id
--   FROM public.journal_claims jc
--   WHERE jc.speaker_contact_id IS NULL
--     AND jc.speaker_label ILIKE 'SPEAKER\_%'
-- ),
-- resolved AS (
--   SELECT
--     t.*,
--     r.contact_id AS new_speaker_contact_id,
--     r.is_internal AS new_speaker_is_internal,
--     r.match_quality,
--     r.match_type
--   FROM targets t
--   LEFT JOIN LATERAL public.resolve_speaker_contact_v2(t.speaker_label, t.project_id, t.call_id) r ON true
--   WHERE r.contact_id IS NOT NULL
-- ),
-- audited AS (
--   INSERT INTO public.speaker_resolution_audit (
--     journal_claim_row_id,
--     claim_id,
--     call_id,
--     project_id,
--     speaker_label,
--     old_speaker_contact_id,
--     new_speaker_contact_id,
--     new_speaker_is_internal,
--     match_quality,
--     match_type
--   )
--   SELECT
--     journal_claim_row_id,
--     claim_id,
--     call_id,
--     project_id,
--     speaker_label,
--     old_speaker_contact_id,
--     new_speaker_contact_id,
--     new_speaker_is_internal,
--     match_quality,
--     match_type
--   FROM resolved
--   RETURNING journal_claim_row_id, new_speaker_contact_id, new_speaker_is_internal
-- )
-- UPDATE public.journal_claims jc
-- SET
--   speaker_contact_id = a.new_speaker_contact_id,
--   speaker_is_internal = a.new_speaker_is_internal
-- FROM audited a
-- WHERE jc.id = a.journal_claim_row_id
--   AND jc.speaker_contact_id IS NULL;
--
-- COMMIT;
