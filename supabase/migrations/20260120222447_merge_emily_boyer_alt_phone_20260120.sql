
-- Merge Emily Boyer (alt) into main record's secondary_phone, then delete duplicate
UPDATE contacts 
SET secondary_phone = '+17064741044'
WHERE id = '05734746-d040-43ab-8bcd-d860c693031b';

-- Delete the alt record
DELETE FROM contacts 
WHERE name = 'Emily Boyer (alt)' AND phone = '+17064741044';
;
