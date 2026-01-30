
-- =============================================================================
-- MIGRATION: Wire review_queue feedback to affinity learning
-- AUTHOR: DATA
-- DATE: 2026-01-19
-- PURPOSE: Close the learning loop - human corrections train affinities
-- =============================================================================

-- Function to process review feedback into affinity updates
CREATE OR REPLACE FUNCTION process_review_feedback()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_contact_id uuid;
  v_project_id uuid;
  v_action text;
  v_result jsonb;
BEGIN
  -- Only process when status changes to 'resolved'
  IF NEW.status != 'resolved' OR OLD.status = 'resolved' THEN
    RETURN NEW;
  END IF;
  
  -- Get the interaction's contact_id and project_id
  SELECT contact_id, project_id 
  INTO v_contact_id, v_project_id
  FROM interactions 
  WHERE id = NEW.interaction_id;
  
  -- Determine action based on resolution_action
  CASE NEW.resolution_action
    WHEN 'attributed' THEN
      -- Human confirmed this contact → project mapping
      v_action := 'confirm';
    WHEN 'rejected', 'reassigned' THEN
      -- Human rejected the proposed mapping
      v_action := 'reject';
    ELSE
      -- dismissed, deferred, etc. - no affinity change
      RETURN NEW;
  END CASE;
  
  -- Skip if we don't have both contact and project
  IF v_contact_id IS NULL OR v_project_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Call the affinity feedback function
  SELECT upsert_affinity_feedback(
    v_contact_id,
    v_project_id,
    v_action,
    'review_queue'  -- source
  ) INTO v_result;
  
  -- Log to override_log for audit trail
  INSERT INTO override_log (
    entity_type,
    entity_id,
    field_name,
    from_value,
    to_value,
    user_id,
    reason,
    review_queue_id
  ) VALUES (
    'correspondent_project_affinity',
    v_contact_id,
    'weight',
    NULL,
    v_result->>'weight',
    COALESCE(NEW.resolved_by, 'system'),
    'Review feedback: ' || v_action || ' for project',
    NEW.id
  );
  
  RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_review_feedback_to_affinity ON review_queue;

CREATE TRIGGER trg_review_feedback_to_affinity
AFTER UPDATE ON review_queue
FOR EACH ROW
WHEN (NEW.status = 'resolved')
EXECUTE FUNCTION process_review_feedback();

-- Add comment for documentation
COMMENT ON FUNCTION process_review_feedback() IS 
'Processes review queue resolutions into affinity learning. Called by trigger when review_queue.status changes to resolved.
- attributed → confirm affinity (weight +1)
- rejected/reassigned → reject affinity (weight -1)
- dismissed/deferred → no change';

COMMENT ON TRIGGER trg_review_feedback_to_affinity ON review_queue IS
'Closes the learning loop: human corrections train correspondent_project_affinity weights';
;
