
-- =============================================================================
-- REPAIR INFRASTRUCTURE FOR CALLS_RAW PHONE BACKFILL
-- Requested by BESIDE-1 for replay harness support
-- =============================================================================

-- 1. BACKLOG VIEW: Canonical definition of "missing phone" rows
-- This is the single source of truth for repair backlog tracking
CREATE OR REPLACE VIEW v_calls_raw_phone_backlog AS
SELECT 
  interaction_id,
  event_at_utc,
  direction,
  other_party_phone,
  owner_phone,
  CASE WHEN transcript IS NOT NULL AND length(transcript) > 10 THEN true ELSE false END as has_transcript,
  CASE WHEN summary IS NOT NULL AND length(summary) > 5 THEN true ELSE false END as has_summary,
  CASE WHEN recording_url IS NOT NULL THEN true ELSE false END as has_recording_url,
  beside_note_url,
  zap_id,
  pipeline_version,
  ingested_at_utc,
  -- Repair priority: higher = easier to repair
  CASE 
    WHEN transcript IS NOT NULL AND length(transcript) > 10 THEN 'A_high_confidence'
    WHEN summary IS NOT NULL AND length(summary) > 5 THEN 'B_medium_confidence'
    ELSE 'C_needs_external_lookup'
  END as repair_priority
FROM calls_raw
WHERE other_party_phone IS NULL;

COMMENT ON VIEW v_calls_raw_phone_backlog IS 
'Canonical backlog of calls_raw rows missing other_party_phone. Use for tracking repair progress to zero.';

-- 2. BACKLOG SUMMARY VIEW: Quick metrics for dashboards
CREATE OR REPLACE VIEW v_calls_raw_phone_backlog_summary AS
SELECT 
  repair_priority,
  COUNT(*) as row_count,
  MIN(event_at_utc) as oldest_event,
  MAX(event_at_utc) as newest_event
FROM v_calls_raw_phone_backlog
GROUP BY repair_priority
UNION ALL
SELECT 
  'TOTAL' as repair_priority,
  COUNT(*) as row_count,
  MIN(event_at_utc) as oldest_event,
  MAX(event_at_utc) as newest_event
FROM v_calls_raw_phone_backlog;

-- 3. REPAIR STAGING TABLE: Safe intake for replay payloads
CREATE TABLE IF NOT EXISTS repair_payloads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id text NOT NULL,
  payload_json jsonb NOT NULL,
  source text NOT NULL DEFAULT 'manual',  -- 'zapier_export', 'pipedream_history', 'manual', 'beside_api'
  inserted_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'skipped')),
  error_message text,
  result_json jsonb,
  CONSTRAINT repair_payloads_interaction_id_source_unique UNIQUE (interaction_id, source)
);

CREATE INDEX IF NOT EXISTS idx_repair_payloads_status ON repair_payloads(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_repair_payloads_interaction_id ON repair_payloads(interaction_id);

COMMENT ON TABLE repair_payloads IS 
'Staging table for repair harness. Insert original Zapier/Pipedream payloads here for safe processing.';

-- 4. REPAIR FUNCTION: Constrained update that respects write policy
-- Write policy: phones/names = COALESCE (trigger), transcript/summary/recording_url = REPLACE if non-empty
CREATE OR REPLACE FUNCTION apply_repair_payload(p_interaction_id text, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_old_record calls_raw%ROWTYPE;
  v_new_phone text;
  v_new_transcript text;
  v_new_summary text;
  v_new_recording_url text;
  v_changes jsonb := '{}'::jsonb;
  v_fields_updated int := 0;
BEGIN
  -- Get existing record
  SELECT * INTO v_old_record FROM calls_raw WHERE interaction_id = p_interaction_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'interaction_id_not_found',
      'interaction_id', p_interaction_id
    );
  END IF;
  
  -- Extract fields from payload (try multiple paths)
  v_new_phone := COALESCE(
    p_payload->>'other_party_phone',
    p_payload->'signal'->>'other_party_phone',
    p_payload->'signal'->'raw_event'->>'other_party_phone'
  );
  
  v_new_transcript := COALESCE(
    p_payload->>'transcript',
    p_payload->'signal'->>'transcript'
  );
  
  v_new_summary := COALESCE(
    p_payload->>'summary',
    p_payload->'signal'->>'summary'
  );
  
  v_new_recording_url := COALESCE(
    p_payload->>'recording_url',
    p_payload->'signal'->>'recording_url'
  );
  
  -- Build update (trigger handles COALESCE for phones, we handle REPLACE policy for content)
  UPDATE calls_raw SET
    -- Phones: trigger will COALESCE, but we pass through anyway
    other_party_phone = COALESCE(v_new_phone, other_party_phone),
    -- Content: REPLACE if new value is non-empty
    transcript = CASE 
      WHEN v_new_transcript IS NOT NULL AND length(v_new_transcript) > 10 THEN v_new_transcript 
      ELSE transcript 
    END,
    summary = CASE 
      WHEN v_new_summary IS NOT NULL AND length(v_new_summary) > 5 THEN v_new_summary 
      ELSE summary 
    END,
    recording_url = CASE 
      WHEN v_new_recording_url IS NOT NULL THEN v_new_recording_url 
      ELSE recording_url 
    END
  WHERE interaction_id = p_interaction_id;
  
  -- Track what changed
  IF v_old_record.other_party_phone IS NULL AND v_new_phone IS NOT NULL THEN
    v_changes := v_changes || jsonb_build_object('other_party_phone', jsonb_build_object('old', null, 'new', v_new_phone));
    v_fields_updated := v_fields_updated + 1;
  END IF;
  
  IF v_new_transcript IS NOT NULL AND length(v_new_transcript) > 10 AND 
     (v_old_record.transcript IS NULL OR v_old_record.transcript != v_new_transcript) THEN
    v_changes := v_changes || jsonb_build_object('transcript', 'replaced');
    v_fields_updated := v_fields_updated + 1;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'interaction_id', p_interaction_id,
    'fields_updated', v_fields_updated,
    'changes', v_changes,
    'applied_at', now()
  );
END;
$$;

COMMENT ON FUNCTION apply_repair_payload IS 
'Safe repair function. Phones use COALESCE (via trigger). Content (transcript/summary/recording_url) uses REPLACE-if-non-empty policy.';

-- 5. REPAIR VALIDATION FUNCTION: Check if repair succeeded
CREATE OR REPLACE FUNCTION validate_repair(p_interaction_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_cr calls_raw%ROWTYPE;
  v_int record;
  v_issues text[] := ARRAY[]::text[];
BEGIN
  -- Get calls_raw record
  SELECT * INTO v_cr FROM calls_raw WHERE interaction_id = p_interaction_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'error', 'not_found_in_calls_raw');
  END IF;
  
  -- Get interactions record for comparison
  SELECT contact_phone, project_id INTO v_int FROM interactions WHERE interaction_id = p_interaction_id;
  
  -- Check phone populated
  IF v_cr.other_party_phone IS NULL THEN
    v_issues := array_append(v_issues, 'other_party_phone_still_null');
  END IF;
  
  -- Check transcript exists
  IF v_cr.transcript IS NULL OR length(v_cr.transcript) < 10 THEN
    v_issues := array_append(v_issues, 'transcript_missing_or_short');
  END IF;
  
  -- Check interactions alignment (if exists)
  IF v_int IS NOT NULL AND v_int.contact_phone IS NULL AND v_cr.other_party_phone IS NOT NULL THEN
    v_issues := array_append(v_issues, 'interactions_contact_phone_not_synced');
  END IF;
  
  RETURN jsonb_build_object(
    'valid', array_length(v_issues, 1) IS NULL,
    'interaction_id', p_interaction_id,
    'other_party_phone', v_cr.other_party_phone,
    'has_transcript', v_cr.transcript IS NOT NULL AND length(v_cr.transcript) > 10,
    'has_summary', v_cr.summary IS NOT NULL,
    'has_recording_url', v_cr.recording_url IS NOT NULL,
    'issues', v_issues,
    'checked_at', now()
  );
END;
$$;

COMMENT ON FUNCTION validate_repair IS 
'Validates repair succeeded: phone populated, transcript present, no derived table drift.';
;
