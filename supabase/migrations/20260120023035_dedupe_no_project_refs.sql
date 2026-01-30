
-- Only delete duplicates that have NO project_contacts references
-- First, get all contacts with project references
WITH contacts_with_projects AS (
    SELECT DISTINCT contact_id FROM project_contacts
),
-- Find duplicate phones where the contact has NO project reference
duplicates_to_delete AS (
    SELECT id FROM (
        SELECT c.id, c.phone,
               ROW_NUMBER() OVER (PARTITION BY c.phone ORDER BY c.created_at) as rn
        FROM contacts c
        WHERE c.phone IN (
            SELECT phone FROM contacts GROUP BY phone HAVING COUNT(*) > 1
        )
        AND c.id NOT IN (SELECT contact_id FROM contacts_with_projects)
    ) t 
    WHERE rn > 1
)
DELETE FROM contacts WHERE id IN (SELECT id FROM duplicates_to_delete);
;
