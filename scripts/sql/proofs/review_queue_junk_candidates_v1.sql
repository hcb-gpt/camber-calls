-- Candidate spans for retroactive junk-call cleanup (read-only proof).
-- Mirrors ai-router/process-call conservative junk prefilter heuristics.
-- Run: scripts/query.sh --file scripts/sql/proofs/review_queue_junk_candidates_v1.sql

WITH pending_queue AS (
  SELECT DISTINCT rq.span_id, rq.interaction_id
  FROM public.review_queue rq
  WHERE rq.status = 'pending'
    AND rq.span_id IS NOT NULL
),
latest_attr AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.decision,
    sa.needs_review,
    sa.reasoning,
    sa.attributed_at
  FROM public.span_attributions sa
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST
),
features AS (
  SELECT
    pq.interaction_id,
    pq.span_id,
    la.decision,
    la.needs_review,
    la.attributed_at,
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
scored AS (
  SELECT
    f.*,
    LOWER(f.transcript_segment) ~ '(leave (me )?(a )?message|mailbox is (full|not set up)|cannot take your c[a]ll|after the tone|please record your message)' AS voicemail_pattern,
    LOWER(f.transcript_segment) ~ '(bad service|c[a]ll (dropped|failed|disconnected)|can( not|''t)?\\s+hear (me|you))' AS connection_failure_pattern,
    LOWER(f.transcript_segment) ~ '(estimate|proposal|contract|invoice|deposit|permit|schedule|change order|install(ation)?|cabinet|countertop|tile|plumbing|electrical|\\$\\s*\\d+)' AS substantive_pattern
  FROM features f
),
classified AS (
  SELECT
    s.*,
    (
      (s.voicemail_pattern = true AND s.word_count <= 80)
      OR
      (s.connection_failure_pattern = true AND s.word_count <= 40 AND s.substantive_pattern = false)
      OR
      (
        s.word_count > 0
        AND s.word_count < 20
        AND (s.speaker_turns <= 1 OR (s.duration_seconds IS NOT NULL AND s.duration_seconds < 15))
        AND s.substantive_pattern = false
      )
    ) AS is_junk_candidate
  FROM scored s
)
SELECT
  c.interaction_id,
  c.span_id,
  c.decision,
  c.needs_review,
  c.word_count,
  c.speaker_turns,
  c.duration_seconds,
  c.voicemail_pattern,
  c.connection_failure_pattern,
  c.substantive_pattern,
  LEFT(REPLACE(c.transcript_segment, E'\n', ' '), 220) AS transcript_snippet
FROM classified c
WHERE c.is_junk_candidate = true
ORDER BY c.word_count ASC, c.duration_seconds ASC NULLS FIRST, c.interaction_id ASC
LIMIT 500;
