WITH /* deepgram_transcript_dup_metrics_v0: summary */ dg AS (
  SELECT interaction_id, transcript_variant, keywords_enabled
  FROM public.transcripts_comparison
  WHERE engine = 'deepgram'
),
null_dupes AS (
  SELECT interaction_id, COUNT(*) AS c
  FROM dg
  WHERE transcript_variant IS NULL
  GROUP BY 1
  HAVING COUNT(*) > 1
)
SELECT
  now() AS measured_at_utc,
  (SELECT COUNT(*) FROM dg) AS deepgram_rows,
  (SELECT COUNT(DISTINCT interaction_id) FROM dg) AS deepgram_interactions,
  (SELECT COUNT(*) FROM dg WHERE transcript_variant IS NULL) AS null_variant_rows,
  (SELECT COUNT(*) FROM null_dupes) AS interaction_ids_with_null_variant_dupes,
  (SELECT COALESCE(SUM(c - 1), 0) FROM null_dupes) AS extra_rows_from_null_variant_dupes
;

WITH /* deepgram_transcript_dup_metrics_v0: top dup interaction_ids */ dg AS (
  SELECT interaction_id, transcript_variant, keywords_enabled, speaker_count, word_count, duration_seconds
  FROM public.transcripts_comparison
  WHERE engine = 'deepgram'
),
dupes AS (
  SELECT interaction_id
  FROM dg
  WHERE transcript_variant IS NULL
  GROUP BY 1
  HAVING COUNT(*) > 1
)
SELECT
  dg.interaction_id,
  COUNT(*) AS rows_total,
  COUNT(*) FILTER (WHERE dg.transcript_variant IS NULL) AS null_variant_rows,
  COUNT(*) FILTER (WHERE dg.keywords_enabled IS TRUE) AS keywords_enabled_true_rows,
  MAX(dg.speaker_count) AS max_speaker_count,
  MAX(dg.word_count) AS max_word_count,
  MAX(dg.duration_seconds) AS max_duration_seconds
FROM dg
JOIN dupes d USING (interaction_id)
GROUP BY 1
ORDER BY null_variant_rows DESC, rows_total DESC, interaction_id ASC
LIMIT 50;

WITH /* deepgram_transcript_dup_metrics_v0: null-variant distribution */ dg AS (
  SELECT keywords_enabled
  FROM public.transcripts_comparison
  WHERE engine = 'deepgram'
    AND transcript_variant IS NULL
)
SELECT
  keywords_enabled,
  COUNT(*) AS row_count
FROM dg
GROUP BY 1
ORDER BY row_count DESC;

