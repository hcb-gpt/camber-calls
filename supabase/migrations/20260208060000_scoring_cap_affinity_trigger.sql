-- scoring_cap_affinity_trigger
--
-- Problem: `update_correspondent_project_affinity()` increments confirmation_count
-- on every UPDATE of interactions.project_id, which can happen multiple times per
-- interaction due to pipeline retries/rescoring. This inflates affinity weights.
--
-- Fix: Cap scoring to a single contribution per interaction by suppressing any
-- subsequent UPDATE where the interaction already has a non-null project_id.
-- Emit an audit entry to pipeline_logs when suppression occurs.

CREATE OR REPLACE FUNCTION update_correspondent_project_affinity()
RETURNS TRIGGER AS $$
BEGIN
  -- Nothing to do if we don't have the attribution inputs.
  IF NEW.project_id IS NULL OR NEW.contact_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Scoring cap: suppress duplicate updates that re-set the same project_id.
  -- (Postgres UPDATE triggers fire if project_id is in the SET list even if the value is unchanged.)
  IF TG_OP = 'UPDATE' AND OLD.project_id IS NOT NULL AND OLD.project_id = NEW.project_id THEN
    INSERT INTO pipeline_logs (
      interaction_id,
      channel,
      zap_version,
      event_at_utc,
      event_at_local,
      log_level,
      future_proof_json
    )
    VALUES (
      NEW.interaction_id,
      'scoring_cap',
      NEW.source_zap,
      NEW.event_at_utc,
      NEW.event_at_local,
      'info',
      jsonb_build_object(
        'type', 'duplicate_affinity_score_suppressed',
        'reason', 'project_id unchanged; suppressing duplicate affinity increment',
        'contact_id', NEW.contact_id,
        'old_project_id', OLD.project_id,
        'new_project_id', NEW.project_id
      )
    );

    RETURN NEW;
  END IF;

  INSERT INTO correspondent_project_affinity (
    contact_id,
    project_id,
    weight,
    confirmation_count,
    last_interaction_at,
    source
  )
  VALUES (
    NEW.contact_id,
    NEW.project_id,
    1.0,
    1,
    NEW.event_at_utc,
    'auto_derived'
  )
  ON CONFLICT (contact_id, project_id)
  DO UPDATE SET
    confirmation_count = correspondent_project_affinity.confirmation_count + 1,
    last_interaction_at = GREATEST(correspondent_project_affinity.last_interaction_at, NEW.event_at_utc),
    updated_at = NOW();

  -- Recalculate weights for this contact (NULLIF prevents division by zero).
  UPDATE correspondent_project_affinity cpa
  SET weight = cpa.confirmation_count::numeric / NULLIF(total.cnt, 0)::numeric
  FROM (
    SELECT contact_id, SUM(confirmation_count) as cnt
    FROM correspondent_project_affinity
    WHERE contact_id = NEW.contact_id
    GROUP BY contact_id
  ) total
  WHERE cpa.contact_id = NEW.contact_id
    AND cpa.contact_id = total.contact_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_correspondent_project_affinity IS
  'Auto-maintains correspondent_project_affinity on interaction upsert. Includes a scoring cap: only the first project_id assignment for an interaction contributes to affinity; later updates are suppressed + logged to pipeline_logs.';
