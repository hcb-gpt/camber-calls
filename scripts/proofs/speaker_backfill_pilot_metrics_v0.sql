WITH /* speaker_backfill_pilot_metrics_v0: deterministic eligibility + expected resolution */ unresolved AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.claim_id,
    jc.call_id,
    jc.project_id,
    jc.speaker_label
  FROM public.journal_claims jc
  WHERE jc.speaker_label ~ '^SPEAKER_[0-9]+$'
    AND jc.speaker_contact_id IS NULL
),
latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.direction,
    cr.owner_phone,
    cr.other_party_phone,
    cr.owner_name,
    cr.other_party_name,
    cr.event_at_utc
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
best_deepgram AS (
  SELECT DISTINCT ON (tc.interaction_id)
    tc.interaction_id AS call_id,
    tc.speaker_count,
    tc.words,
    tc.transcript
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
  ORDER BY
    tc.interaction_id,
    (tc.words IS NOT NULL) DESC,
    tc.speaker_count DESC NULLS LAST,
    tc.word_count DESC NULLS LAST,
    tc.id DESC
),
enriched AS (
  SELECT
    u.*,
    lc.direction,
    lc.owner_phone,
    lc.other_party_phone,
    lc.owner_name,
    lc.other_party_name,
    tc.speaker_count,
    tc.words,
    tc.transcript,
    NULLIF(regexp_replace(u.speaker_label, '[^0-9]', '', 'g'), '')::INT AS speaker_num,
    (
      SELECT (w->>'speaker')::INT
      FROM jsonb_array_elements(tc.words) w
      WHERE w ? 'speaker' AND w ? 'start'
      ORDER BY (w->>'start')::NUMERIC ASC
      LIMIT 1
    ) AS first_speaker_from_words,
    NULLIF((regexp_match(tc.transcript, '(?m)^SPEAKER_([0-9]+):'))[1], '')::INT AS first_speaker_from_transcript
  FROM unresolved u
  LEFT JOIN latest_call lc ON lc.call_id = u.call_id
  LEFT JOIN best_deepgram tc ON tc.call_id = u.call_id
),
calc AS (
  SELECT
    e.*,
    COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) AS first_speaker,
    CASE
      WHEN e.direction ~* '^(in|inbound|incoming)$' THEN
        CASE WHEN e.speaker_num = COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) THEN 'owner' ELSE 'other_party' END
      WHEN e.direction ~* '^(out|outbound|outgoing)$' THEN
        CASE WHEN e.speaker_num = COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) THEN 'other_party' ELSE 'owner' END
      ELSE NULL
    END AS inferred_role
  FROM enriched e
),
eligible AS (
  SELECT *
  FROM calc
  WHERE first_speaker IS NOT NULL
    AND speaker_count = 2
    AND inferred_role IS NOT NULL
),
resolved AS (
  SELECT
    el.*,
    CASE
      WHEN inferred_role = 'owner' AND owner_phone IS NOT NULL THEN (SELECT contact_id FROM public.lookup_contact_by_phone(owner_phone) LIMIT 1)
      WHEN inferred_role = 'other_party' AND other_party_phone IS NOT NULL THEN (SELECT contact_id FROM public.lookup_contact_by_phone(other_party_phone) LIMIT 1)
      WHEN inferred_role = 'owner' AND owner_name IS NOT NULL AND btrim(owner_name) != '' THEN (SELECT contact_id FROM public.resolve_speaker_contact(owner_name, project_id) LIMIT 1)
      WHEN inferred_role = 'other_party' AND other_party_name IS NOT NULL AND btrim(other_party_name) != '' THEN (SELECT contact_id FROM public.resolve_speaker_contact(other_party_name, project_id) LIMIT 1)
      ELSE NULL
    END AS resolved_contact_id,
    CASE
      WHEN inferred_role = 'owner' AND owner_phone IS NOT NULL AND (SELECT contact_id FROM public.lookup_contact_by_phone(owner_phone) LIMIT 1) IS NOT NULL THEN 'phone_owner'
      WHEN inferred_role = 'other_party' AND other_party_phone IS NOT NULL AND (SELECT contact_id FROM public.lookup_contact_by_phone(other_party_phone) LIMIT 1) IS NOT NULL THEN 'phone_other_party'
      WHEN inferred_role = 'owner' AND owner_name IS NOT NULL AND btrim(owner_name) != '' AND (SELECT contact_id FROM public.resolve_speaker_contact(owner_name, project_id) LIMIT 1) IS NOT NULL THEN 'name_owner'
      WHEN inferred_role = 'other_party' AND other_party_name IS NOT NULL AND btrim(other_party_name) != '' AND (SELECT contact_id FROM public.resolve_speaker_contact(other_party_name, project_id) LIMIT 1) IS NOT NULL THEN 'name_other_party'
      ELSE 'unresolved'
    END AS match_bucket
  FROM eligible el
)
SELECT
  now() AS measured_at_utc,
  (SELECT COUNT(*) FROM unresolved) AS unresolved_diarized_claims,
  (SELECT COUNT(*) FROM eligible) AS deterministic_eligible_claims,
  (SELECT COUNT(DISTINCT call_id) FROM eligible) AS deterministic_eligible_calls,
  (SELECT COUNT(*) FROM resolved WHERE resolved_contact_id IS NOT NULL) AS expected_resolvable_claims,
  (SELECT COUNT(*) FROM resolved WHERE resolved_contact_id IS NULL) AS expected_unresolved_claims
;

WITH /* speaker_backfill_pilot_metrics_v0: match bucket breakdown */ unresolved AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.call_id,
    jc.project_id,
    jc.speaker_label
  FROM public.journal_claims jc
  WHERE jc.speaker_label ~ '^SPEAKER_[0-9]+$'
    AND jc.speaker_contact_id IS NULL
),
latest_call AS (
  SELECT DISTINCT ON (cr.interaction_id)
    cr.interaction_id AS call_id,
    cr.direction,
    cr.owner_phone,
    cr.other_party_phone,
    cr.owner_name,
    cr.other_party_name,
    cr.event_at_utc
  FROM public.calls_raw cr
  ORDER BY
    cr.interaction_id,
    cr.event_at_utc DESC NULLS LAST,
    cr.ingested_at_utc DESC NULLS LAST,
    cr.received_at_utc DESC NULLS LAST,
    cr.id DESC
),
best_deepgram AS (
  SELECT DISTINCT ON (tc.interaction_id)
    tc.interaction_id AS call_id,
    tc.speaker_count,
    tc.words,
    tc.transcript
  FROM public.transcripts_comparison tc
  WHERE tc.engine = 'deepgram'
  ORDER BY
    tc.interaction_id,
    (tc.words IS NOT NULL) DESC,
    tc.speaker_count DESC NULLS LAST,
    tc.word_count DESC NULLS LAST,
    tc.id DESC
),
enriched AS (
  SELECT
    u.*,
    lc.direction,
    lc.owner_phone,
    lc.other_party_phone,
    lc.owner_name,
    lc.other_party_name,
    tc.speaker_count,
    tc.words,
    tc.transcript,
    NULLIF(regexp_replace(u.speaker_label, '[^0-9]', '', 'g'), '')::INT AS speaker_num,
    (
      SELECT (w->>'speaker')::INT
      FROM jsonb_array_elements(tc.words) w
      WHERE w ? 'speaker' AND w ? 'start'
      ORDER BY (w->>'start')::NUMERIC ASC
      LIMIT 1
    ) AS first_speaker_from_words,
    NULLIF((regexp_match(tc.transcript, '(?m)^SPEAKER_([0-9]+):'))[1], '')::INT AS first_speaker_from_transcript
  FROM unresolved u
  LEFT JOIN latest_call lc ON lc.call_id = u.call_id
  LEFT JOIN best_deepgram tc ON tc.call_id = u.call_id
),
calc AS (
  SELECT
    e.*,
    COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) AS first_speaker,
    CASE
      WHEN e.direction ~* '^(in|inbound|incoming)$' THEN
        CASE WHEN e.speaker_num = COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) THEN 'owner' ELSE 'other_party' END
      WHEN e.direction ~* '^(out|outbound|outgoing)$' THEN
        CASE WHEN e.speaker_num = COALESCE(e.first_speaker_from_words, e.first_speaker_from_transcript) THEN 'other_party' ELSE 'owner' END
      ELSE NULL
    END AS inferred_role
  FROM enriched e
),
eligible AS (
  SELECT *
  FROM calc
  WHERE first_speaker IS NOT NULL
    AND speaker_count = 2
    AND inferred_role IS NOT NULL
),
resolved AS (
  SELECT
    el.*,
    CASE
      WHEN inferred_role = 'owner' AND owner_phone IS NOT NULL AND (SELECT contact_id FROM public.lookup_contact_by_phone(owner_phone) LIMIT 1) IS NOT NULL THEN 'phone_owner'
      WHEN inferred_role = 'other_party' AND other_party_phone IS NOT NULL AND (SELECT contact_id FROM public.lookup_contact_by_phone(other_party_phone) LIMIT 1) IS NOT NULL THEN 'phone_other_party'
      WHEN inferred_role = 'owner' AND owner_name IS NOT NULL AND btrim(owner_name) != '' AND (SELECT contact_id FROM public.resolve_speaker_contact(owner_name, project_id) LIMIT 1) IS NOT NULL THEN 'name_owner'
      WHEN inferred_role = 'other_party' AND other_party_name IS NOT NULL AND btrim(other_party_name) != '' AND (SELECT contact_id FROM public.resolve_speaker_contact(other_party_name, project_id) LIMIT 1) IS NOT NULL THEN 'name_other_party'
      ELSE 'unresolved'
    END AS match_bucket
  FROM eligible el
)
SELECT
  match_bucket,
  COUNT(*) AS claim_count,
  COUNT(DISTINCT call_id) AS call_count
FROM resolved
GROUP BY 1
ORDER BY 2 DESC, 1 ASC;

