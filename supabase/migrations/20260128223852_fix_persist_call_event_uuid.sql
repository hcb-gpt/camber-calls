
-- Fix: calls_raw.id is UUID, not bigint
CREATE OR REPLACE FUNCTION persist_call_event(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_interaction_id text;
  v_phone text;
  v_zap_id text;
  v_run_id text;
  v_gate_status text := 'pass';
  v_gate_reasons jsonb := '[]'::jsonb;
  v_i1_phone boolean;
  v_i2_unique boolean;
  v_i5_lineage boolean;
  v_triage_action text := 'auto_persist';
  v_audit_id bigint;
  v_existing_id uuid;  -- Fixed: UUID not bigint
BEGIN
  -- Extract key fields
  v_interaction_id := payload->>'interaction_id';
  v_phone := COALESCE(
    payload->>'other_party_phone',
    payload->'_zapier_meta'->>'from_phone',
    payload->'_zapier_meta'->>'to_phone'
  );
  v_zap_id := COALESCE(
    payload->'_zapier_meta'->>'zap_id',
    payload->'capture_lineage'->>'zap_id'
  );
  v_run_id := COALESCE(
    payload->'_zapier_meta'->>'run_id',
    payload->'capture_lineage'->>'run_id'
  );
  
  -- Normalize empty strings to NULL
  IF v_phone = '' THEN v_phone := NULL; END IF;
  IF v_zap_id = '' THEN v_zap_id := NULL; END IF;
  IF v_run_id = '' THEN v_run_id := NULL; END IF;
  
  -- ============================================
  -- INVARIANT CHECKS
  -- ============================================
  
  -- I1: Phone present and valid E.164
  v_i1_phone := (v_phone IS NOT NULL AND v_phone ~ '^\+[0-9]{10,15}$');
  IF NOT v_i1_phone THEN
    v_gate_reasons := v_gate_reasons || '"missing_or_invalid_phone"'::jsonb;
  END IF;
  
  -- I2: Unique interaction_id (check for existing)
  SELECT id INTO v_existing_id FROM calls_raw WHERE interaction_id = v_interaction_id;
  v_i2_unique := (v_existing_id IS NULL);
  IF NOT v_i2_unique THEN
    v_gate_reasons := v_gate_reasons || '"duplicate_interaction_id"'::jsonb;
  END IF;
  
  -- I5: Lineage present
  v_i5_lineage := (v_zap_id IS NOT NULL OR v_run_id IS NOT NULL);
  IF NOT v_i5_lineage THEN
    v_gate_reasons := v_gate_reasons || '"missing_lineage"'::jsonb;
  END IF;
  
  -- ============================================
  -- GATE DECISION
  -- ============================================
  
  IF NOT v_i2_unique THEN
    v_gate_status := 'fail';
    v_triage_action := 'reject';
  ELSIF NOT v_i1_phone AND NOT v_i5_lineage THEN
    v_gate_status := 'needs_human';
    v_triage_action := 'queue_human';
  ELSIF NOT v_i1_phone THEN
    v_gate_status := 'needs_human';
    v_triage_action := 'queue_human';
  ELSIF NOT v_i5_lineage THEN
    v_gate_status := 'pass';
    v_triage_action := 'auto_persist';
    v_gate_reasons := v_gate_reasons || '"lineage_missing_warning"'::jsonb;
  ELSE
    v_gate_status := 'pass';
    v_triage_action := 'auto_persist';
  END IF;
  
  -- ============================================
  -- LOG TO EVENT_AUDIT
  -- ============================================
  
  INSERT INTO event_audit (
    interaction_id,
    gate_status,
    gate_reasons,
    i1_phone_present,
    i2_unique_id,
    i5_lineage_present,
    triage_action,
    source_system,
    source_run_id,
    source_zap_id,
    raw_payload_hash,
    pipeline_version,
    processed_by
  ) VALUES (
    v_interaction_id,
    v_gate_status,
    v_gate_reasons,
    v_i1_phone,
    v_i2_unique,
    v_i5_lineage,
    v_triage_action,
    COALESCE(payload->>'source_system', 'unknown'),
    v_run_id,
    v_zap_id,
    encode(sha256(payload::text::bytea), 'hex'),
    payload->>'pipeline_version',
    'persist_call_event_v1'
  )
  RETURNING id INTO v_audit_id;
  
  -- ============================================
  -- CONDITIONAL PERSIST TO CALLS_RAW
  -- ============================================
  
  IF v_triage_action = 'auto_persist' THEN
    INSERT INTO calls_raw (
      interaction_id,
      other_party_phone,
      direction,
      event_at_utc,
      transcript,
      summary,
      recording_url,
      beside_note_url,
      zap_id,
      zap_step_id,
      raw_snapshot_json,
      pipeline_version,
      ingested_at_utc
    ) VALUES (
      v_interaction_id,
      v_phone,
      payload->>'direction',
      (payload->>'event_at_utc')::timestamptz,
      payload->>'transcript',
      payload->>'summary',
      payload->>'recording_url',
      payload->>'beside_note_url',
      v_zap_id,
      v_run_id,
      payload,
      COALESCE(payload->>'pipeline_version', 'persist_call_event_v1'),
      now()
    )
    ON CONFLICT (interaction_id) DO NOTHING;
    
    UPDATE event_audit 
    SET persisted_to_calls_raw = true, 
        persisted_at_utc = now()
    WHERE id = v_audit_id;
  END IF;
  
  RETURN jsonb_build_object(
    'audit_id', v_audit_id,
    'interaction_id', v_interaction_id,
    'gate_status', v_gate_status,
    'gate_reasons', v_gate_reasons,
    'triage_action', v_triage_action,
    'persisted', (v_triage_action = 'auto_persist'),
    'i1_phone', v_i1_phone,
    'i2_unique', v_i2_unique,
    'i5_lineage', v_i5_lineage
  );
END;
$$;
;
