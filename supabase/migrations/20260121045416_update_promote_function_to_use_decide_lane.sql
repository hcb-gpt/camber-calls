-- Update promote_journal_claims_to_belief to use decide_lane() for routing
-- Replaces old start_sec/end_sec pointer check with Policy v1 gates

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
  v_claims_staged INT := 0;
  v_claim RECORD;
  v_decision RECORD;
  v_new_claim_id UUID;
  v_normalized_type text;
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

  -- 3. Process each claim using decide_lane()
  FOR v_claim IN 
    SELECT * FROM journal_claims 
    WHERE run_id = p_run_id AND active = true
  LOOP
    -- Call decide_lane for routing decision
    SELECT * INTO v_decision FROM decide_lane(v_claim, '{}'::jsonb);
    
    -- Normalize type for belief_claims enum
    v_normalized_type := CASE v_claim.claim_type
      WHEN 'deadline' THEN 'commitment'
      WHEN 'question' THEN 'open_loop'
      WHEN 'blocker' THEN 'risk'
      WHEN 'concern' THEN 'risk'
      WHEN 'fact' THEN 'state'
      WHEN 'update' THEN 'event'
      WHEN 'requirement' THEN 'request'
      WHEN 'preference' THEN 'request'
      ELSE v_claim.claim_type
    END;

    IF v_decision.lane = 'PROMOTE' THEN
      -- Promote to belief_claims
      v_new_claim_id := gen_random_uuid();
      
      INSERT INTO belief_claims (
        id,
        project_id,
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
        updated_at,
        source_run_id,
        journal_claim_id
      ) VALUES (
        v_new_claim_id,
        v_claim.claim_project_id,
        -- Map to belief_claims enum
        CASE v_normalized_type
          WHEN 'commitment' THEN 'commitment'::claim_type_enum
          WHEN 'decision' THEN 'decision'::claim_type_enum
          WHEN 'risk' THEN 'risk'::claim_type_enum
          WHEN 'open_loop' THEN 'open_loop'::claim_type_enum
          WHEN 'state' THEN 'state'::claim_type_enum
          WHEN 'event' THEN 'event'::claim_type_enum
          WHEN 'request' THEN 'request'::claim_type_enum
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
        COALESCE(v_claim.attribution_confidence, 0.70),
        'Extracted from call ' || v_claim.call_id || ' via decide_lane PROMOTE',
        'active'::lifecycle_enum,
        NULL,  -- speaker_entity_id NULL for v1
        'firsthand'::origin_kind_enum,
        v_event_at,
        NOW(),
        v_claim.claim_text,
        NOW(),
        NOW(),
        p_run_id,
        v_claim.id
      );
      
      -- Create claim_pointer with char-based spans
      INSERT INTO claim_pointers (
        id, claim_id, source_type, source_id, 
        ts_start, ts_end,  -- NULL for v1 (no audio timestamps)
        created_at
      ) VALUES (
        gen_random_uuid(),
        v_new_claim_id,
        'transcript_text'::source_type_enum,
        v_claim.call_id,
        NULL,  -- ts_start NULL (using char spans instead)
        NULL,  -- ts_end NULL
        NOW()
      );
      v_pointers_created := v_pointers_created + 1;
      
      -- Log to promotion_log
      INSERT INTO promotion_log (run_id, claim_id, journal_claim_id)
      VALUES (p_run_id, v_new_claim_id, v_claim.id);
      
      v_claims_promoted := v_claims_promoted + 1;

    ELSIF v_decision.lane = 'REVIEW' THEN
      -- Route to journal_review_queue with idempotent upsert
      INSERT INTO journal_review_queue (
        id, run_id, call_id, item_type, item_id, reason, data, status, created_at
      ) VALUES (
        gen_random_uuid(),
        p_run_id,
        v_claim.call_id,
        'claim',
        v_claim.id,
        v_decision.reason_code,
        jsonb_build_object(
          'claim_id', v_claim.claim_id,
          'claim_text', v_claim.claim_text,
          'claim_type', v_claim.claim_type,
          'normalized_type', v_normalized_type,
          'project_id', v_claim.claim_project_id,
          'reason_detail', v_decision.reason_detail
        ),
        'pending',
        NOW()
      )
      ON CONFLICT (item_id, reason) WHERE item_type = 'claim'
      DO UPDATE SET
        data = EXCLUDED.data,
        run_id = EXCLUDED.run_id;
      
      v_claims_routed := v_claims_routed + 1;

    ELSE
      -- STAGE or DROP: no action, claim stays in journal_claims only
      v_claims_staged := v_claims_staged + 1;
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
    'claims_staged', v_claims_staged,
    'policy_version', 'v1_decide_lane'
  );
END;
$function$;

COMMENT ON FUNCTION public.promote_journal_claims_to_belief(uuid) IS 
'Promotes journal_claims to belief_claims using decide_lane() for Policy v1 routing. PROMOTE→belief_claims, REVIEW→journal_review_queue, STAGE→no-op.';;
