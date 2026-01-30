-- Larry Fitzgerald has 2 records: cell phone (2 interactions) and company phone (0 interactions)
-- Keep the active record, add company phone as secondary, delete duplicate

-- 1. Add company phone as secondary to the active record
UPDATE contacts 
SET secondary_phone = '+17065579010',
    role = COALESCE(role, 'vendor'),
    notes = COALESCE(notes, '') || ' | Merged: company phone was separate record'
WHERE id = '969ab7c5-a306-43da-8c9e-20aea318bdf6';

-- 2. Delete the duplicate record with 0 interactions
DELETE FROM contacts 
WHERE id = 'a80c201a-72e1-4422-b362-3d2cc18a088a';;
