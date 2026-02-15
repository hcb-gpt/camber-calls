-- Phase 3 / dev-2 promotion batch (idempotent)
-- Promotes high-signal pointer-backed journal_claims into belief_claims and
-- writes canonical transcript span pointers in claim_pointers.

WITH candidates AS (
  SELECT
    jc.id AS journal_claim_id,
    jc.claim_project_id AS project_id,
    jc.call_id,
    jc.run_id,
    jc.claim_text,
    jc.claim_type,
    jc.epistemic_status,
    jc.warrant_level,
    jc.attribution_confidence,
    jc.char_start,
    jc.char_end,
    jc.span_text,
    jc.span_hash,
    COALESCE(cr.event_at_utc, jc.created_at, NOW()) AS event_at_utc
  FROM public.journal_claims jc
  LEFT JOIN public.calls_raw cr
    ON cr.interaction_id = jc.call_id
  WHERE jc.active = true
    AND jc.claim_project_id IS NOT NULL
    AND jc.pointer_type = 'transcript_span'
    AND jc.char_start IS NOT NULL
    AND jc.char_end IS NOT NULL
    AND jc.span_hash IS NOT NULL
    AND jc.claim_type IN ('decision', 'commitment', 'risk', 'open_loop', 'schedule', 'blocker', 'deadline')
    AND NOT EXISTS (
      SELECT 1
      FROM public.belief_claims bc
      WHERE bc.journal_claim_id = jc.id
    )
),
inserted_claims AS (
  INSERT INTO public.belief_claims (
    id,
    claim_type,
    epistemic_status,
    warrant_level,
    confidence,
    confidence_rationale,
    lifecycle,
    project_id,
    origin_kind,
    event_at_utc,
    ingested_at_utc,
    short_text,
    created_at,
    updated_at,
    source_run_id,
    journal_claim_id
  )
  SELECT
    gen_random_uuid(),
    CASE c.claim_type
      WHEN 'decision' THEN 'decision'::public.claim_type_enum
      WHEN 'commitment' THEN 'commitment'::public.claim_type_enum
      WHEN 'risk' THEN 'risk'::public.claim_type_enum
      WHEN 'open_loop' THEN 'open_loop'::public.claim_type_enum
      WHEN 'blocker' THEN 'risk'::public.claim_type_enum
      WHEN 'schedule' THEN 'commitment'::public.claim_type_enum
      WHEN 'deadline' THEN 'commitment'::public.claim_type_enum
      ELSE 'state'::public.claim_type_enum
    END,
    CASE
      WHEN c.epistemic_status = 'inferred' THEN 'inferred'::public.epistemic_status_enum
      WHEN c.claim_type = 'decision' THEN 'decided'::public.epistemic_status_enum
      WHEN c.claim_type IN ('commitment', 'schedule', 'deadline') THEN 'promised'::public.epistemic_status_enum
      WHEN c.epistemic_status = 'uncertain' THEN 'disputed'::public.epistemic_status_enum
      ELSE 'reported'::public.epistemic_status_enum
    END,
    CASE c.warrant_level
      WHEN 'high' THEN 'execution_accept'::public.warrant_level_enum
      ELSE 'planning_accept'::public.warrant_level_enum
    END,
    LEAST(
      1::numeric,
      GREATEST(
        0::numeric,
        COALESCE(
          c.attribution_confidence,
          CASE c.warrant_level
            WHEN 'high' THEN 0.90
            WHEN 'medium' THEN 0.75
            WHEN 'low' THEN 0.60
            ELSE 0.70
          END
        )
      )
    ),
    'batch_v1 promotion from journal_claims (pointer-backed high-signal set)',
    'active'::public.lifecycle_enum,
    c.project_id,
    'firsthand'::public.origin_kind_enum,
    c.event_at_utc,
    NOW(),
    LEFT(c.claim_text, 1000),
    NOW(),
    NOW(),
    c.run_id,
    c.journal_claim_id
  FROM candidates c
  ON CONFLICT DO NOTHING
  RETURNING id, journal_claim_id
),
inserted_pointers AS (
  INSERT INTO public.claim_pointers (
    id,
    claim_id,
    source_type,
    source_id,
    ts_start,
    ts_end,
    created_at,
    char_start,
    char_end,
    span_text,
    span_hash,
    evidence_event_id
  )
  SELECT
    gen_random_uuid(),
    ic.id,
    'transcript_text'::public.source_type_enum,
    c.call_id,
    NULL,
    NULL,
    NOW(),
    c.char_start,
    c.char_end,
    c.span_text,
    c.span_hash,
    ee.evidence_event_id
  FROM inserted_claims ic
  JOIN candidates c
    ON c.journal_claim_id = ic.journal_claim_id
  LEFT JOIN public.evidence_events ee
    ON ee.source_id = c.call_id
  RETURNING id
)
SELECT
  (SELECT COUNT(*) FROM candidates) AS candidate_count,
  (SELECT COUNT(*) FROM inserted_claims) AS claims_inserted,
  (SELECT COUNT(*) FROM inserted_pointers) AS pointers_inserted;
