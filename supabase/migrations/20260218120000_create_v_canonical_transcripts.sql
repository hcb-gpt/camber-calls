-- Canonical transcript view: picks the best transcript per interaction_id
-- using a priority-ranked DISTINCT ON with empty-transcript filtering.
--
-- Priority order:
--   0  deepgram + keywords_on   (best quality, vocab-boosted)
--   1  deepgram + keywords_off  (baseline deepgram)
--   2  deepgram + NULL variant   (legacy rows before GATE 4)
--   3  beside                    (phone-native transcript)
--   4  everything else
--
-- Rows with NULL or empty transcript are excluded.

CREATE OR REPLACE VIEW v_canonical_transcripts AS
SELECT DISTINCT ON (interaction_id)
  id,
  interaction_id,
  engine,
  model,
  transcript_variant,
  transcript,
  words,
  speaker_count,
  has_speaker_labels,
  word_count,
  duration_seconds,
  created_at,
  engine || '/' || COALESCE(transcript_variant, 'default') AS transcript_source
FROM transcripts_comparison
WHERE transcript IS NOT NULL
  AND LENGTH(transcript) > 0
ORDER BY
  interaction_id,
  CASE
    WHEN engine = 'deepgram' AND transcript_variant = 'keywords_on'  THEN 0
    WHEN engine = 'deepgram' AND transcript_variant = 'keywords_off' THEN 1
    WHEN engine = 'deepgram' AND transcript_variant IS NULL           THEN 2
    WHEN engine = 'beside'                                            THEN 3
    ELSE 4
  END,
  created_at DESC;

COMMENT ON VIEW v_canonical_transcripts IS
  'One best transcript per interaction_id, ranked by engine/variant quality. Excludes empty transcripts.';

-- Supporting composite index for the DISTINCT ON lookup path
CREATE INDEX IF NOT EXISTS idx_tc_canonical_lookup
  ON transcripts_comparison (interaction_id, engine, transcript_variant, created_at DESC);
