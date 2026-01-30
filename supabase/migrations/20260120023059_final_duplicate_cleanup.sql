
-- Handle remaining duplicates

-- Ginger Gray - delete the one without project refs
DELETE FROM contacts 
WHERE phone = '+17704558878' 
AND company = 'Alex Smith Garden Design Ltd'
AND id NOT IN (SELECT contact_id FROM project_contacts WHERE contact_id IS NOT NULL);

-- Alyssa Swick duplicate - delete one of the Alyssa records (keep the one with more refs)
DELETE FROM contacts
WHERE id IN (
    SELECT id FROM (
        SELECT c.id,
               ROW_NUMBER() OVER (
                   PARTITION BY c.phone, c.name 
                   ORDER BY (SELECT COUNT(*) FROM project_contacts pc WHERE pc.contact_id = c.id) DESC
               ) as rn
        FROM contacts c
        WHERE c.phone = '+17065437358' AND c.name = 'Alyssa Swick'
    ) t WHERE rn > 1
);

-- Note: Sarah Hahn and Alyssa Swick share phone - this is valid (office line shared between employees)
UPDATE contacts SET 
    notes = COALESCE(notes, '') || ' | Shares phone with Sarah Hahn (same office)'
WHERE phone = '+17065437358' AND name = 'Alyssa Swick';

UPDATE contacts SET 
    notes = COALESCE(notes, '') || ' | Shares phone with Alyssa Swick (same office)'
WHERE phone = '+17065437358' AND name = 'Sarah Hahn';
;
