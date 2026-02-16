-- Parent interaction transcript mismatch proof (read-only).
-- Finds interactions where transcript_chars is zero while active conversation_spans contain text.
-- Run: scripts/query.sh --file scripts/sql/proofs/interaction_transcript_parent_mismatch_v1.sql

WITH span_rollup AS (
  SELECT
    cs.interaction_id,
    SUM(LENGTH(COALESCE(cs.transcript_segment, '')))::int AS span_chars,
    COUNT(*)::int AS span_count
  FROM public.conversation_spans cs
  WHERE COALESCE(cs.is_superseded, false) = false
  GROUP BY cs.interaction_id
),
latest_calls_raw AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id,
    LENGTH(COALESCE(cr.transcript, ''))::int AS calls_raw_chars
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST
)
SELECT
  i.interaction_id,
  COALESCE(i.transcript_chars, 0) AS interaction_transcript_chars,
  sr.span_chars,
  sr.span_count,
  COALESCE(lcr.calls_raw_chars, 0) AS calls_raw_chars,
  i.needs_review,
  i.review_reasons
FROM public.interactions i
JOIN span_rollup sr ON sr.interaction_id = i.interaction_id
LEFT JOIN latest_calls_raw lcr ON lcr.interaction_id = i.interaction_id
WHERE COALESCE(i.transcript_chars, 0) = 0
  AND sr.span_chars > 0
ORDER BY sr.span_chars DESC, i.interaction_id ASC;
