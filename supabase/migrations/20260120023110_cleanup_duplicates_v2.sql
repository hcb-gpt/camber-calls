
-- Remove duplicate Ginger Gray (keep one with most data)
DELETE FROM contacts 
WHERE phone = '+17704558878' 
AND name = 'Ginger Gray'
AND id NOT IN (
    SELECT id FROM contacts 
    WHERE phone = '+17704558878' 
    ORDER BY created_at ASC 
    LIMIT 1
);

-- Note shared phones
UPDATE contacts SET notes = COALESCE(notes, '') || ' | Phone shared with Alyssa Swick'
WHERE name = 'Sarah Hahn' AND phone = '+17065437358' AND notes NOT LIKE '%shared%';

UPDATE contacts SET notes = COALESCE(notes, '') || ' | Phone shared with Sarah Hahn'
WHERE name = 'Alyssa Swick' AND phone = '+17065437358' AND notes NOT LIKE '%shared%';
;
