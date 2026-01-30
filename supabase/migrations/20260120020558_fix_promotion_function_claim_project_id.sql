
-- Fix promote_journal_claims_to_belief to use claim_project_id and source_run_id
CREATE OR REPLACE FUNCTION public.promote_journal_claims_to_belief(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run RECORD;
  v_event_at TIMESTAMPTZ;
  v_claims_promoted INT := 0;
  v_pointers_created INT := 0;
  v_claims_routed INT := 0;
  v_claims_skipped_null_project INT := 0;
  v_claim RECORD;
  v_new_claim_id UUID;
BEGIN
  -- 1. Validate run exists and succeeded
  SELECT * INTO v_run 
  FROM journal_runs 
  WHERE run_id = p_run_id AND status = 'success';
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Run % not found or status is not success', p_run_id;
  END IF;

  -- 2. Get event timestamp from calls_raw
  SELECT event_at_utc INTO v_event_at
  FROM calls_raw
  WHERE interaction_id = v_run.call_id;

  IF v_event_at IS NULL THEN
    v_event_at := NOW(); -- fallback if no event time
  END IF;

  -- 3. Process each claim
  FOR v_claim IN 
    SELECT * FROM journal_claims 
    WHERE run_id = p_run_id AND active = true
  LOOP
    -- v1.4.3 FIX: Skip claims where claim_project_id is NULL (ambiguous attribution)
    IF v_claim.claim_project_id IS NULL THEN
      v_claims_skipped_null_project := v_claims_skipped_null_project + 1;
      CONTINUE;
    END IF;

    -- Check if timestamps are NULL -> route to review
    IF v_claim.start_sec IS NULL OR v_claim.end_sec IS NULL THEN
      -- Route to journal_review_queue
      INSERT INTO journal_review_queue (
        id, run_id, item_type, item_id, reason, data, status, created_at
      ) VALUES (
        gen_random_uuid(),
        p_run_id,
        'claim',
        v_claim.id,
        'missing_pointer_time',
        jsonb_build_object(
          'claim_id', v_claim.claim_id,
          'claim_text', v_claim.claim_text,
          'claim_type', v_claim.claim_type,
          'call_id', v_claim.call_id,
          'project_id', v_claim.claim_project_id
        ),
        'pending',
        NOW()
      );
      v_claims_routed := v_claims_routed + 1;
    ELSE
      -- Promote to belief_claims
      v_new_claim_id := gen_random_uuid();
      
      INSERT INTO belief_claims (
        id,
        project_id,              -- v1.4.3 FIX: Use claim_project_id
        source_run_id,           -- v1.4.3 FIX: Add source_run_id for rollback
        claim_type,
        epistemic_status,
        warrant_level,
        confidence,
        confidence_rationale,
        lifecycle,
        speaker_entity_id,
        origin_kind,
        event_at_utc,
        ingested_at_utc,
        short_text,
        created_at,
        updated_at
      ) VALUES (
        v_new_claim_id,
        v_claim.claim_project_id,  -- v1.4.3 FIX: Use claim-level attribution
        p_run_id,                  -- v1.4.3 FIX: Enable rollback-by-run
        -- Map claim_type (J0 TEXT -> J1 ENUM)
        CASE v_claim.claim_type
          WHEN 'commitment' THEN 'commitment'::claim_type_enum
          WHEN 'deadline' THEN 'commitment'::claim_type_enum
          WHEN 'decision' THEN 'decision'::claim_type_enum
          WHEN 'blocker' THEN 'risk'::claim_type_enum
          WHEN 'requirement' THEN 'request'::claim_type_enum
          WHEN 'preference' THEN 'request'::claim_type_enum
          WHEN 'concern' THEN 'risk'::claim_type_enum
          WHEN 'fact' THEN 'state'::claim_type_enum
          WHEN 'question' THEN 'open_loop'::claim_type_enum
          WHEN 'update' THEN 'event'::claim_type_enum
          ELSE 'state'::claim_type_enum
        END,
        -- Map epistemic_status
        CASE v_claim.epistemic_status
          WHEN 'stated' THEN 'reported'::epistemic_status_enum
          WHEN 'inferred' THEN 'inferred'::epistemic_status_enum
          WHEN 'uncertain' THEN 'reported'::epistemic_status_enum
          ELSE 'reported'::epistemic_status_enum
        END,
        -- Map warrant_level
        CASE v_claim.warrant_level
          WHEN 'high' THEN 'execution_accept'::warrant_level_enum
          WHEN 'medium' THEN 'planning_accept'::warrant_level_enum
          WHEN 'low' THEN 'planning_accept'::warrant_level_enum
          ELSE 'planning_accept'::warrant_level_enum
        END,
        -- Confidence: use attribution_confidence if available, else derive from warrant
        COALESCE(
          v_claim.attribution_confidence,
          CASE v_claim.warrant_level
            WHEN 'high' THEN 0.85
            WHEN 'medium' THEN 0.70
            WHEN 'low' THEN 0.50
            ELSE 0.60
          END
        ),
        'Extracted from call ' || v_claim.call_id,
        'active'::lifecycle_enum,
        NULL,  -- speaker_entity_id NULL for v1
        'firsthand'::origin_kind_enum,
        v_event_at,
        NOW(),
        v_claim.claim_text,
        NOW(),
        NOW()
      );
      
      -- Create claim_pointer
      INSERT INTO claim_pointers (
        id, claim_id, source_type, source_id, ts_start, ts_end, created_at
      ) VALUES (
        gen_random_uuid(),
        v_new_claim_id,
        'transcript_text'::source_type_enum,
        v_claim.call_id,
        v_claim.start_sec,
        v_claim.end_sec,
        NOW()
      );
      v_pointers_created := v_pointers_created + 1;
      
      -- Log to promotion_log
      INSERT INTO promotion_log (run_id, claim_id, journal_claim_id)
      VALUES (p_run_id, v_new_claim_id, v_claim.id);
      
      v_claims_promoted := v_claims_promoted + 1;
    END IF;
  END LOOP;

  -- Return summary
  RETURN jsonb_build_object(
    'run_id', p_run_id,
    'call_id', v_run.call_id,
    'event_at_utc', v_event_at,
    'claims_promoted', v_claims_promoted,
    'pointers_created', v_pointers_created,
    'claims_routed_to_review', v_claims_routed,
    'claims_skipped_null_project', v_claims_skipped_null_project,
    'review_reasons', jsonb_build_object(
      'missing_pointer_time', v_claims_routed,
      'null_claim_project_id', v_claims_skipped_null_project
    )
  );
END;
$function$;

COMMENT ON FUNCTION promote_journal_claims_to_belief(uuid) IS 
'v1.4.3: Uses claim_project_id (not legacy project_id), sets source_run_id for rollback, skips NULL attribution';
;
