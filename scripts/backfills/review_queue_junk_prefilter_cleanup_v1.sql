-- review_queue_junk_prefilter_cleanup_v1
--
-- Purpose:
-- - retroactively close junk-call review queue rows that should have been filtered
--   by the ai-router/process-call junk prefilter
-- - align latest span_attributions to decision='none' + needs_review=false
--
-- Safety:
-- - only touches status='pending' review_queue rows with non-null span_id
-- - only targets latest span_attributions rows where needs_review=true and decision in ('review','none')
-- - uses conservative voicemail/connection/minimal-content heuristics with substantive fail-open
--
-- Preconditions:
-- - run read-only proof first:
--   scripts/query.sh --file scripts/sql/proofs/review_queue_junk_candidates_v1.sql
-- - coordinate with STRAT before mutating data

BEGIN;

WITH pending_queue AS (
  SELECT DISTINCT rq.span_id, rq.interaction_id
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
    AND rq.span_id IS NOT NULL
),
latest_attr AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.id,
    sa.span_id,
    sa.decision,
    sa.needs_review
  FROM public.span_attributions sa
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST
),
features AS (
  SELECT
    pq.interaction_id,
    pq.span_id,
    la.id AS span_attr_id,
    la.decision,
    la.needs_review,
    COALESCE(s.transcript_segment, '') AS transcript_segment,
    CASE
      WHEN s.time_end_sec IS NOT NULL AND s.time_start_sec IS NOT NULL AND s.time_end_sec > s.time_start_sec
        THEN ROUND(s.time_end_sec - s.time_start_sec)::int
      ELSE NULL
    END AS duration_seconds,
    COALESCE(
      CARDINALITY(
        REGEXP_SPLIT_TO_ARRAY(
          NULLIF(
            TRIM(
              REGEXP_REPLACE(
                LOWER(COALESCE(s.transcript_segment, '')),
                '[^a-z0-9'' ]+',
                ' ',
                'g'
              )
            ),
            ''
          ),
          E'\\s+'
        )
      ),
      0
    ) AS word_count,
    COALESCE(
      (
        SELECT COUNT(*)
        FROM REGEXP_MATCHES(COALESCE(s.transcript_segment, ''), '(^|\\n)\\s*[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s*:', 'g')
      ),
      0
    ) AS speaker_turns
  FROM pending_queue pq
  JOIN latest_attr la ON la.span_id = pq.span_id
  LEFT JOIN public.conversation_spans s ON s.id = pq.span_id
  WHERE la.needs_review = true
    AND la.decision IN ('review', 'none')
),
target_spans AS (
  SELECT
    f.span_attr_id,
    f.span_id
  FROM features f
  WHERE
    (
      LOWER(f.transcript_segment) ~ '(leave (me )?(a )?message|mailbox is (full|not set up)|cannot take your c[a]ll|after the tone|please record your message)'
      AND f.word_count <= 80
    )
    OR
    (
      LOWER(f.transcript_segment) ~ '(bad service|c[a]ll (dropped|failed|disconnected)|can( not|''t)?\\s+hear (me|you))'
      AND f.word_count <= 40
      AND LOWER(f.transcript_segment) !~ '(estimate|proposal|contract|invoice|deposit|permit|schedule|change order|install(ation)?|cabinet|countertop|tile|plumbing|electrical|\\$\\s*\\d+)'
    )
    OR
    (
      f.word_count > 0
      AND f.word_count < 20
      AND (f.speaker_turns <= 1 OR (f.duration_seconds IS NOT NULL AND f.duration_seconds < 15))
      AND LOWER(f.transcript_segment) !~ '(estimate|proposal|contract|invoice|deposit|permit|schedule|change order|install(ation)?|cabinet|countertop|tile|plumbing|electrical|\\$\\s*\\d+)'
    )
),
updated_attributions AS (
  UPDATE public.span_attributions sa
  SET
    decision = 'none',
    project_id = NULL,
    applied_project_id = NULL,
    attribution_lock = NULL,
    needs_review = false,
    attribution_source = 'junk_call_prefilter_backfill_v1',
    reasoning = TRIM(COALESCE(sa.reasoning, '') || ' [junk_call_filtered retroactive_cleanup_v1]'),
    attributed_by = 'DATA_BACKFILL',
    attributed_at = now()
  FROM target_spans t
  WHERE sa.id = t.span_attr_id
  RETURNING sa.span_id
),
updated_review_queue AS (
  UPDATE public.review_queue rq
  SET
    status = 'resolved',
    resolved_at = now(),
    resolved_by = 'DATA_BACKFILL',
    resolution_action = 'auto_resolve',
    resolution_notes = '[junk_prefilter_cleanup_v1] resolved by conservative junk-call heuristic'
  WHERE rq.status = 'pending'
    AND rq.span_id IN (SELECT span_id FROM updated_attributions)
  RETURNING rq.id
)
SELECT
  (SELECT COUNT(*) FROM updated_attributions) AS span_attributions_updated,
  (SELECT COUNT(*) FROM updated_review_queue) AS review_queue_rows_resolved;

COMMIT;
