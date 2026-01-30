
-- =============================================================================
-- PARITY CHECK FUNCTION + ADDITIONAL LINEAGE COLUMNS
-- Requested by BESIDE-1 for standardized phone reconciliation
-- =============================================================================

-- 1. Add remaining lineage columns (zapier_run_id, zapier_account_id, received_at_utc)
ALTER TABLE calls_raw 
  ADD COLUMN IF NOT EXISTS zapier_run_id text,
  ADD COLUMN IF NOT EXISTS zapier_account_id text,
  ADD COLUMN IF NOT EXISTS inbox_id text,
  ADD COLUMN IF NOT EXISTS source_received_at_utc timestamptz;

COMMENT ON COLUMN calls_raw.zapier_run_id IS 'Zapier execution run ID for lineage tracking';
COMMENT ON COLUMN calls_raw.zapier_account_id IS 'Zapier account ID for lineage tracking';
COMMENT ON COLUMN calls_raw.inbox_id IS 'Beside inbox ID if available';
COMMENT ON COLUMN calls_raw.source_received_at_utc IS 'Timestamp when Zapier received the event from Beside';

-- 2. Create standardized parity check function
CREATE OR REPLACE FUNCTION check_phone_parity(p_interaction_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_cr record;
  v_int record;
  v_contact record;
  v_issues text[] := ARRAY[]::text[];
  v_status text;
BEGIN
  -- Get calls_raw record (authoritative)
  SELECT 
    interaction_id,
    other_party_phone,
    owner_phone,
    other_party_name,
    owner_name,
    event_at_utc,
    pipeline_version,
    ingested_at_utc
  INTO v_cr
  FROM calls_raw 
  WHERE interaction_id = p_interaction_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'NOT_FOUND',
      'interaction_id', p_interaction_id,
      'error', 'not_found_in_calls_raw'
    );
  END IF;
  
  -- Get interactions record (derived)
  SELECT 
    interaction_id,
    contact_phone,
    owner_phone,
    contact_name,
    owner_name,
    contact_id,
    project_id
  INTO v_int
  FROM interactions 
  WHERE interaction_id = p_interaction_id;
  
  -- Get contact record if contact_id exists
  IF v_int.contact_id IS NOT NULL THEN
    SELECT id, phone, name INTO v_contact
    FROM contacts 
    WHERE id = v_int.contact_id;
  END IF;
  
  -- Check for issues
  
  -- Issue: calls_raw.other_party_phone is null
  IF v_cr.other_party_phone IS NULL THEN
    v_issues := array_append(v_issues, 'calls_raw_other_party_phone_null');
  END IF;
  
  -- Issue: interactions exists but contact_phone doesn't match calls_raw
  IF v_int IS NOT NULL THEN
    IF v_cr.other_party_phone IS NOT NULL AND v_int.contact_phone IS NULL THEN
      v_issues := array_append(v_issues, 'interactions_contact_phone_null_but_calls_raw_has_phone');
    END IF;
    
    IF v_cr.other_party_phone IS NOT NULL AND v_int.contact_phone IS NOT NULL 
       AND v_cr.other_party_phone != v_int.contact_phone THEN
      v_issues := array_append(v_issues, 'phone_mismatch_calls_raw_vs_interactions');
    END IF;
  END IF;
  
  -- Issue: contact exists but phone doesn't match
  IF v_contact IS NOT NULL AND v_contact.phone IS NOT NULL THEN
    IF v_cr.other_party_phone IS NOT NULL AND v_contact.phone != v_cr.other_party_phone THEN
      v_issues := array_append(v_issues, 'phone_mismatch_calls_raw_vs_contact');
    END IF;
  END IF;
  
  -- Determine status
  IF array_length(v_issues, 1) IS NULL THEN
    v_status := 'PASS';
  ELSIF 'calls_raw_other_party_phone_null' = ANY(v_issues) THEN
    v_status := 'FAIL_MISSING_PHONE';
  ELSE
    v_status := 'FAIL_DRIFT';
  END IF;
  
  RETURN jsonb_build_object(
    'status', v_status,
    'interaction_id', p_interaction_id,
    'calls_raw', jsonb_build_object(
      'other_party_phone', v_cr.other_party_phone,
      'owner_phone', v_cr.owner_phone,
      'other_party_name', v_cr.other_party_name,
      'event_at_utc', v_cr.event_at_utc,
      'pipeline_version', v_cr.pipeline_version
    ),
    'interactions', CASE WHEN v_int IS NOT NULL THEN jsonb_build_object(
      'contact_phone', v_int.contact_phone,
      'owner_phone', v_int.owner_phone,
      'contact_id', v_int.contact_id,
      'project_id', v_int.project_id
    ) ELSE null END,
    'contact', CASE WHEN v_contact IS NOT NULL THEN jsonb_build_object(
      'id', v_contact.id,
      'phone', v_contact.phone,
      'name', v_contact.name
    ) ELSE null END,
    'issues', v_issues,
    'checked_at', now()
  );
END;
$$;

COMMENT ON FUNCTION check_phone_parity IS 
'Single-query parity check: shows calls_raw phones, interactions phones, contact phone, and PASS/FAIL status.';

-- 3. Create parity summary view for bulk analysis
CREATE OR REPLACE VIEW v_phone_parity_summary AS
WITH parity AS (
  SELECT 
    cr.interaction_id,
    cr.other_party_phone as cr_phone,
    cr.owner_phone as cr_owner,
    i.contact_phone as int_phone,
    i.owner_phone as int_owner,
    c.phone as contact_phone,
    i.contact_id,
    cr.pipeline_version,
    cr.event_at_utc,
    CASE 
      WHEN cr.other_party_phone IS NULL THEN 'FAIL_MISSING_PHONE'
      WHEN i.contact_phone IS NULL AND cr.other_party_phone IS NOT NULL THEN 'WARN_INT_PHONE_NULL'
      WHEN cr.other_party_phone != COALESCE(i.contact_phone, cr.other_party_phone) THEN 'FAIL_DRIFT'
      ELSE 'PASS'
    END as status
  FROM calls_raw cr
  LEFT JOIN interactions i ON cr.interaction_id = i.interaction_id
  LEFT JOIN contacts c ON i.contact_id = c.id
)
SELECT 
  status,
  COUNT(*) as row_count,
  array_agg(interaction_id ORDER BY event_at_utc DESC) FILTER (WHERE status != 'PASS') as sample_ids
FROM parity
GROUP BY status;

COMMENT ON VIEW v_phone_parity_summary IS 
'Bulk parity summary showing distribution of PASS/FAIL statuses across all calls.';

-- 4. Detection query for rows needing recovery (as a view)
CREATE OR REPLACE VIEW v_recovery_candidates AS
SELECT 
  cr.interaction_id,
  cr.event_at_utc,
  cr.other_party_phone as current_phone,
  cr.beside_note_url,
  cr.zap_id,
  cr.zapier_run_id,
  cr.pipeline_version,
  cr.ingested_at_utc,
  -- Check if raw_snapshot_json might have the phone
  cr.raw_snapshot_json->'signal'->>'other_party_phone' as snapshot_phone,
  cr.raw_snapshot_json->>'other_party_phone' as snapshot_phone_alt,
  CASE 
    WHEN cr.raw_snapshot_json->'signal'->>'other_party_phone' IS NOT NULL THEN 'recoverable_from_snapshot'
    WHEN cr.raw_snapshot_json->>'other_party_phone' IS NOT NULL THEN 'recoverable_from_snapshot_alt'
    WHEN cr.beside_note_url IS NOT NULL THEN 'has_beside_url_for_lookup'
    ELSE 'needs_zapier_history_lookup'
  END as recovery_path
FROM calls_raw cr
WHERE cr.other_party_phone IS NULL
ORDER BY cr.event_at_utc DESC;

COMMENT ON VIEW v_recovery_candidates IS 
'Rows needing phone recovery, with suggested recovery path based on available data.';
;
