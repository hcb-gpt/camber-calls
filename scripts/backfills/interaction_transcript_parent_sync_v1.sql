-- interaction_transcript_parent_sync_v1
--
-- Purpose:
-- - fix stale parent interaction transcript metadata when transcript_chars=0
--   but active conversation spans contain transcript content
-- - remove stale empty-transcript reason codes from review_reasons
--
-- Preconditions:
-- - run read-only proof first:
--   scripts/query.sh --file scripts/sql/proofs/interaction_transcript_parent_mismatch_v1.sql
-- - coordinate with STRAT before mutation
--
-- Safety:
-- - only updates rows with transcript_chars=0 AND span_chars>0
-- - does not touch interactions with non-zero transcript_chars

BEGIN;

WITH span_rollup AS (
  SELECT
    cs.interaction_id,
    SUM(LENGTH(COALESCE(cs.transcript_segment, '')))::int AS span_chars
  FROM public.conversation_spans cs
  WHERE COALESCE(cs.is_superseded, false) = false
  GROUP BY cs.interaction_id
),
targets AS (
  SELECT
    i.id,
    i.interaction_id,
    i.needs_review,
    COALESCE(i.review_reasons, '{}'::text[]) AS review_reasons,
    sr.span_chars
  FROM public.interactions i
  JOIN span_rollup sr ON sr.interaction_id = i.interaction_id
  WHERE COALESCE(i.transcript_chars, 0) = 0
    AND sr.span_chars > 0
),
normalized AS (
  SELECT
    t.id,
    t.interaction_id,
    t.span_chars,
    t.needs_review,
    ARRAY(
      SELECT reason
      FROM UNNEST(t.review_reasons) reason
      WHERE reason <> 'G4_EMPTY_TRANSCRIPT'
        AND reason <> 'terminal_empty_transcript'
    )::text[] AS cleaned_reasons
  FROM targets t
),
updated AS (
  UPDATE public.interactions i
  SET
    transcript_chars = n.span_chars,
    review_reasons = n.cleaned_reasons,
    needs_review = CASE
      WHEN i.needs_review = true AND COALESCE(array_length(n.cleaned_reasons, 1), 0) = 0 THEN false
      ELSE i.needs_review
    END
  FROM normalized n
  WHERE i.id = n.id
  RETURNING i.interaction_id
)
SELECT
  COUNT(*) AS rows_updated
FROM updated;

COMMIT;
