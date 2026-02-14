-- Restore pointer + project fields in dedup insert RPC.
-- Regression introduced when insert_journal_claims_dedup omitted pointer columns.

CREATE OR REPLACE FUNCTION public.insert_journal_claims_dedup(p_rows jsonb)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  inserted_count bigint;
BEGIN
  WITH rows AS (
    SELECT *
    FROM jsonb_to_recordset(p_rows) AS r(
      claim_id uuid,
      run_id uuid,
      call_id text,
      project_id uuid,
      claim_project_id uuid,
      claim_project_confidence numeric,
      source_span_id uuid,
      claim_type text,
      claim_text text,
      epistemic_status text,
      warrant_level text,
      testimony_type text,
      speaker_label text,
      speaker_contact_id uuid,
      speaker_is_internal boolean,
      start_sec numeric,
      end_sec numeric,
      char_start integer,
      char_end integer,
      span_text text,
      span_hash text,
      pointer_type text,
      relationship text,
      active boolean,
      extraction_model_id text,
      extraction_prompt_version text
    )
  ),
  ins AS (
    INSERT INTO public.journal_claims (
      claim_id,
      run_id,
      call_id,
      project_id,
      claim_project_id,
      claim_project_confidence,
      source_span_id,
      claim_type,
      claim_text,
      epistemic_status,
      warrant_level,
      testimony_type,
      speaker_label,
      speaker_contact_id,
      speaker_is_internal,
      start_sec,
      end_sec,
      char_start,
      char_end,
      span_text,
      span_hash,
      pointer_type,
      relationship,
      active,
      extraction_model_id,
      extraction_prompt_version
    )
    SELECT
      r.claim_id,
      r.run_id,
      r.call_id,
      r.project_id,
      r.claim_project_id,
      r.claim_project_confidence,
      r.source_span_id,
      r.claim_type,
      r.claim_text,
      r.epistemic_status,
      r.warrant_level,
      r.testimony_type,
      r.speaker_label,
      r.speaker_contact_id,
      r.speaker_is_internal,
      r.start_sec,
      r.end_sec,
      r.char_start,
      r.char_end,
      r.span_text,
      r.span_hash,
      COALESCE(r.pointer_type, 'transcript_span')::pointer_type_enum,
      r.relationship,
      COALESCE(r.active, true),
      r.extraction_model_id,
      r.extraction_prompt_version
    FROM rows r
    ON CONFLICT (call_id, claim_type, claim_text, claim_project_id_norm)
      WHERE active = true
    DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO inserted_count FROM ins;

  RETURN inserted_count;
END;
$$;
