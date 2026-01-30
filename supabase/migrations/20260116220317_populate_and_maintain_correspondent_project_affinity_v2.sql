
-- First populate from existing attributed interactions
INSERT INTO correspondent_project_affinity (contact_id, project_id, weight, confirmation_count, last_interaction_at, source)
SELECT 
  c.id as contact_id,
  i.project_id,
  COUNT(*)::numeric / (SELECT COUNT(*) FROM interactions i2 WHERE i2.contact_id = c.id AND i2.project_id IS NOT NULL)::numeric as weight,
  COUNT(*)::integer as confirmation_count,
  MAX(i.event_at_utc) as last_interaction_at,
  'auto_derived' as source
FROM interactions i
JOIN contacts c ON i.contact_id = c.id
WHERE i.project_id IS NOT NULL
  AND c.id IS NOT NULL
GROUP BY c.id, i.project_id
ON CONFLICT (contact_id, project_id) 
DO UPDATE SET 
  confirmation_count = EXCLUDED.confirmation_count,
  weight = EXCLUDED.weight,
  last_interaction_at = EXCLUDED.last_interaction_at,
  updated_at = NOW();

-- Create trigger function to maintain it automatically
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
    UPDATE correspondent_project_affinity cpa
    SET weight = cpa.confirmation_count::numeric / total.cnt::numeric
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

-- Create trigger on interactions table
DROP TRIGGER IF EXISTS trg_update_correspondent_affinity ON interactions;
CREATE TRIGGER trg_update_correspondent_affinity
  AFTER INSERT OR UPDATE OF project_id ON interactions
  FOR EACH ROW
  EXECUTE FUNCTION update_correspondent_project_affinity();
;
