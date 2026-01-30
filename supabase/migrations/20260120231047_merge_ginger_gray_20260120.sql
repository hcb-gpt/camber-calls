-- Merge Ginger Gray into Ginger (Landscaper) 
-- Need to migrate project_contacts first

-- 1. Update project_contacts to point to the surviving record
UPDATE project_contacts 
SET contact_id = 'cc79dcf9-8c3c-4a01-bd9a-c2b3a0be64ac'  -- Ginger (Landscaper)
WHERE contact_id = 'd6e7f890-1234-5678-defa-234567890123';  -- Ginger Gray

-- 2. Update affinity records too
UPDATE correspondent_project_affinity 
SET contact_id = 'cc79dcf9-8c3c-4a01-bd9a-c2b3a0be64ac'
WHERE contact_id = 'd6e7f890-1234-5678-defa-234567890123';

-- 3. Update the main contact record
UPDATE contacts 
SET 
  email = 'ginger@alexsmithgardendesign.com',
  secondary_phone = '+17704558878',
  name = 'Ginger Gray',
  notes = COALESCE(notes, '') || ' | Merged from duplicate record'
WHERE id = 'cc79dcf9-8c3c-4a01-bd9a-c2b3a0be64ac';

-- 4. Delete the duplicate
DELETE FROM contacts WHERE id = 'd6e7f890-1234-5678-defa-234567890123';;
