
-- Parity snapshot function: single query for all phone fields + PASS/FAIL
CREATE OR REPLACE FUNCTION check_phone_parity(p_interaction_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_cr calls_raw%ROWTYPE;
  v_int record;
  v_contact record;
  v_issues text[] := ARRAY[]::text[];
  v_status text;
BEGIN
  -- Get calls_raw
  SELECT * INTO v_cr FROM calls_raw WHERE interaction_id = p_interaction_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'NOT_FOUND',
      'interaction_id', p_interaction_id,
      'error', 'No calls_raw record'
    );
  END IF;
  
  -- Get interactions
  SELECT contact_phone, contact_id, owner_phone INTO v_int 
  FROM interactions WHERE interaction_id = p_interaction_id;
  
  -- Get contact phone if contact_id exists
  IF v_int.contact_id IS NOT NULL THEN
    SELECT phone INTO v_contact FROM contacts WHERE id = v_int.contact_id;
  END IF;
  
  -- Check issues
  IF v_cr.other_party_phone IS NULL THEN
    v_issues := array_append(v_issues, 'calls_raw.other_party_phone IS NULL');
  END IF;
  
  IF v_int IS NOT NULL AND v_int.contact_phone IS NULL AND v_cr.other_party_phone IS NOT NULL THEN
    v_issues := array_append(v_issues, 'interactions.contact_phone NULL but calls_raw has phone');
  END IF;
  
  IF v_int IS NOT NULL AND v_int.contact_phone IS NOT NULL AND v_cr.other_party_phone IS NOT NULL 
     AND v_int.contact_phone != v_cr.other_party_phone THEN
    v_issues := array_append(v_issues, 'phone mismatch: calls_raw != interactions');
  END IF;
  
  -- Determine status
  IF array_length(v_issues, 1) IS NULL THEN
    v_status := 'PASS';
  ELSE
    v_status := 'FAIL';
  END IF;
  
  RETURN jsonb_build_object(
    'status', v_status,
    'interaction_id', p_interaction_id,
    'calls_raw', jsonb_build_object(
      'other_party_phone', v_cr.other_party_phone,
      'owner_phone', v_cr.owner_phone,
      'has_transcript', v_cr.transcript IS NOT NULL AND length(v_cr.transcript) > 10
    ),
    'interactions', CASE WHEN v_int IS NOT NULL THEN jsonb_build_object(
      'contact_phone', v_int.contact_phone,
      'owner_phone', v_int.owner_phone,
      'contact_id', v_int.contact_id
    ) ELSE null END,
    'contact', CASE WHEN v_contact IS NOT NULL THEN jsonb_build_object(
      'phone', v_contact.phone
    ) ELSE null END,
    'issues', v_issues,
    'checked_at', now()
  );
END;
$$;

COMMENT ON FUNCTION check_phone_parity IS 
'Returns PASS/FAIL status comparing calls_raw, interactions, and contacts phone fields for a given interaction_id.';
;
