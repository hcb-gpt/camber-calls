-- Migration: Create RPC that implements the affinity update rule from sensemaking docs
-- confirm → weight +1, confirmation_count +1
-- reject → weight −1, rejection_count −1
-- Uses existing unique constraint on (contact_id, project_id)

CREATE OR REPLACE FUNCTION upsert_affinity_feedback(
  p_contact_id uuid,
  p_project_id uuid,
  p_action text,  -- 'confirm' or 'reject'
  p_source text DEFAULT 'override'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_weight_delta numeric;
  v_result jsonb;
BEGIN
  -- Validate action
  IF p_action NOT IN ('confirm', 'reject') THEN
    RAISE EXCEPTION 'Invalid action: %. Must be confirm or reject.', p_action;
  END IF;
  
  -- Set weight delta based on action
  v_weight_delta := CASE WHEN p_action = 'confirm' THEN 1 ELSE -1 END;
  
  -- Upsert the affinity edge
  INSERT INTO correspondent_project_affinity (
    id,
    contact_id,
    project_id,
    weight,
    confirmation_count,
    rejection_count,
    last_interaction_at,
    source,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    p_contact_id,
    p_project_id,
    GREATEST(0, v_weight_delta),  -- Start at 0 or 1, never negative on first insert
    CASE WHEN p_action = 'confirm' THEN 1 ELSE 0 END,
    CASE WHEN p_action = 'reject' THEN 1 ELSE 0 END,
    now(),
    p_source,
    now(),
    now()
  )
  ON CONFLICT (contact_id, project_id) DO UPDATE SET
    weight = GREATEST(0, correspondent_project_affinity.weight + v_weight_delta),
    confirmation_count = correspondent_project_affinity.confirmation_count + 
      CASE WHEN p_action = 'confirm' THEN 1 ELSE 0 END,
    rejection_count = correspondent_project_affinity.rejection_count + 
      CASE WHEN p_action = 'reject' THEN 1 ELSE 0 END,
    last_interaction_at = now(),
    updated_at = now()
  RETURNING jsonb_build_object(
    'contact_id', contact_id,
    'project_id', project_id,
    'weight', weight,
    'confirmation_count', confirmation_count,
    'rejection_count', rejection_count,
    'action', p_action
  ) INTO v_result;
  
  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION upsert_affinity_feedback IS 'Implements the learning loop rule: confirm → weight+1, reject → weight-1. DEV calls this when human confirms/rejects project attribution.';;
