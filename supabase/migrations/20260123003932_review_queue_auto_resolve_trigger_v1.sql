/*
  review_queue_auto_resolve_trigger_v1.sql

  Purpose:
    Auto-resolve review_queue rows when the parent interaction becomes "resolved"
    (i.e., has BOTH contact_id and project_id populated).

  Notes:
    - Trigger is scoped to updates of (contact_id, project_id) only.
    - No-ops unless it transitions from "missing at least one" -> "both present".
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.auto_resolve_review_queue_on_interaction_resolved()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only act when BOTH are present now, and previously at least one was missing
  IF NEW.contact_id IS NOT NULL
     AND NEW.project_id IS NOT NULL
     AND (OLD.contact_id IS NULL OR OLD.project_id IS NULL) THEN

    UPDATE public.review_queue
    SET
      status = 'resolved',
      resolved_at = NOW(),
      resolved_by = 'AUTO_TRIGGER',
      resolution_action = 'AUTO_RESOLVE',
      resolution_notes = 'Interaction resolved via trigger: contact_id + project_id populated'
    WHERE interaction_id = NEW.id
      AND status = 'pending';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_resolve_review_queue_on_interaction_resolved ON public.interactions;

CREATE TRIGGER trg_auto_resolve_review_queue_on_interaction_resolved
  AFTER UPDATE OF contact_id, project_id ON public.interactions
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_resolve_review_queue_on_interaction_resolved();

COMMIT;
;
