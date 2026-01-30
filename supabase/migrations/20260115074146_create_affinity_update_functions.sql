-- Affinity update rules as RPC functions
-- Rule: high-confidence attribution and human overrides upweight
-- Rule: rejections downweight
-- Rule: decay is simple (applied periodically, not on every call)

-- Function: Update affinity on router attribution (called by pipeline)
CREATE OR REPLACE FUNCTION update_affinity_on_attribution(
  p_contact_id uuid,
  p_project_id uuid,
  p_confidence numeric,
  p_source text DEFAULT 'router_attribution'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_weight_delta numeric;
BEGIN
  -- Only upweight if confidence >= 0.8 (high confidence)
  IF p_confidence >= 0.8 THEN
    v_weight_delta := 0.1 * p_confidence;  -- Scale by confidence
    
    INSERT INTO correspondent_project_affinity 
      (id, contact_id, project_id, weight, confirmation_count, source, last_interaction_at, created_at, updated_at)
    VALUES 
      (gen_random_uuid(), p_contact_id, p_project_id, v_weight_delta, 1, p_source, now(), now(), now())
    ON CONFLICT (contact_id, project_id) DO UPDATE SET
      weight = LEAST(correspondent_project_affinity.weight + v_weight_delta, 2.0),  -- Cap at 2.0
      confirmation_count = correspondent_project_affinity.confirmation_count + 1,
      last_interaction_at = now(),
      updated_at = now();
  END IF;
END;
$$;

-- Function: Update affinity on human override (called by review UI)
CREATE OR REPLACE FUNCTION update_affinity_on_override(
  p_contact_id uuid,
  p_project_id uuid,
  p_is_confirmation boolean  -- true = "yes this is correct", false = "no, wrong project"
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_is_confirmation THEN
    -- Strong upweight on human confirmation
    INSERT INTO correspondent_project_affinity 
      (id, contact_id, project_id, weight, confirmation_count, source, last_interaction_at, created_at, updated_at)
    VALUES 
      (gen_random_uuid(), p_contact_id, p_project_id, 0.3, 1, 'human_override', now(), now(), now())
    ON CONFLICT (contact_id, project_id) DO UPDATE SET
      weight = LEAST(correspondent_project_affinity.weight + 0.3, 2.0),
      confirmation_count = correspondent_project_affinity.confirmation_count + 1,
      source = 'human_override',
      last_interaction_at = now(),
      updated_at = now();
  ELSE
    -- Downweight on rejection
    UPDATE correspondent_project_affinity
    SET 
      weight = GREATEST(weight - 0.2, 0.0),  -- Floor at 0
      rejection_count = COALESCE(rejection_count, 0) + 1,
      updated_at = now()
    WHERE contact_id = p_contact_id AND project_id = p_project_id;
  END IF;
END;
$$;

-- Function: Apply decay to all affinity weights (run weekly via cron or manual)
CREATE OR REPLACE FUNCTION apply_affinity_decay(
  p_decay_factor numeric DEFAULT 0.95  -- 5% decay per period
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows_updated integer;
BEGIN
  UPDATE correspondent_project_affinity
  SET 
    weight = weight * p_decay_factor,
    updated_at = now()
  WHERE weight > 0.01;  -- Don't bother with near-zero weights
  
  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  RETURN v_rows_updated;
END;
$$;

COMMENT ON FUNCTION update_affinity_on_attribution IS 'Called by pipeline: upweights affinity when router confidence >= 0.8';
COMMENT ON FUNCTION update_affinity_on_override IS 'Called by review UI: strong upweight on confirm, downweight on reject';
COMMENT ON FUNCTION apply_affinity_decay IS 'Run periodically (weekly): decays all weights by factor to let old projects fade';;
