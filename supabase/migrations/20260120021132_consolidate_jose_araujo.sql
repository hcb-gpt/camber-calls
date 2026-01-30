
-- Consolidate Jose Araujo records - keep the one with verified phone
-- Add company info from the other record

UPDATE contacts 
SET notes = COALESCE(notes, '') || ' | Also: Dominion Painting',
    company = 'Jayco Innovation Group LLC / Dominion Painting'
WHERE name = 'Jose (Tony) Araujo' AND phone = '+16788591983';

DELETE FROM contacts WHERE name = 'Jose Araujo (Tony)' AND phone = '+14045551234';
;
