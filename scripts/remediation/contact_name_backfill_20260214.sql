-- Backfill calls_raw.other_party_name for resolved calls (DATA-4)
-- Scope: calls where interactions.contact_id is set but calls_raw.other_party_name is NULL

BEGIN;

WITH target AS (
  SELECT cr.interaction_id,
         COALESCE(c.name, i.contact_name) AS resolved_name
  FROM calls_raw cr
  JOIN interactions i ON i.interaction_id = cr.interaction_id
  LEFT JOIN contacts c ON c.id = i.contact_id
  WHERE cr.other_party_name IS NULL
    AND i.contact_id IS NOT NULL
    AND COALESCE(c.name, i.contact_name) IS NOT NULL
)
UPDATE calls_raw cr
SET other_party_name = t.resolved_name
FROM target t
WHERE cr.interaction_id = t.interaction_id;

COMMIT;
