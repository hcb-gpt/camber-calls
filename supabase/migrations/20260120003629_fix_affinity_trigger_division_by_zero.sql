
-- Fix division by zero in affinity trigger
-- Use NULLIF to prevent division by zero when all confirmation_counts are 0

CREATE OR REPLACE FUNCTION update_correspondent_project_affinity()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.project_id IS NOT NULL AND NEW.contact_id IS NOT NULL THEN
    INSERT INTO correspondent_project_affinity (contact_id, project_id, weight, confirmation_count, last_interaction_at, source)
    VALUES (NEW.contact_id, NEW.project_id, 1.0, 1, NEW.event_at_utc, 'auto_derived')
    ON CONFLICT (contact_id, project_id) 
    DO UPDATE SET 
      confirmation_count = correspondent_project_affinity.confirmation_count + 1,
      last_interaction_at = GREATEST(correspondent_project_affinity.last_interaction_at, NEW.event_at_utc),
      updated_at = NOW();
    
    -- Recalculate weights for this contact
    -- Use NULLIF to prevent division by zero when total.cnt = 0
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
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION update_correspondent_project_affinity IS 'Auto-maintains correspondent_project_affinity on interaction upsert. Uses NULLIF to prevent division by zero when all confirmation_counts are 0 (e.g., quarantined floaters).';
;
