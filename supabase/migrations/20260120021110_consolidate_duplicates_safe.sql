
-- Safe consolidation: only delete records with 0 interactions
-- First, update the records we're keeping with secondary phone info

-- Brian Dove: Keep the one with 20 interactions, delete the other
DELETE FROM contacts WHERE id = '8443fb30-e006-4cef-9b2c-a44dd88e5998';

-- Austin Atkinson: Both have 0 interactions, merge into first
UPDATE contacts 
SET notes = COALESCE(notes, '') || ' | Company main: +18339024603'
WHERE id = 'a7ae67a6-7d5a-4dee-a4b3-f017abc95648';

DELETE FROM contacts WHERE id = 'abe0727f-94cf-41a2-8d85-8b80d7b22dad';

-- Calvin Taylor: Delete placeholder number
DELETE FROM contacts WHERE id = '57ec2c87-bbd4-4dff-b994-60576f02658f';

-- Dwayne Brown: Keep +17063191884 (has 3 interactions), add other as secondary
UPDATE contacts 
SET secondary_phone = '+17062836151',
    notes = COALESCE(notes, '') || ' | Company: +17062836151'
WHERE id = 'c7c4190e-05b5-4112-a9fd-88dfb87af777';

DELETE FROM contacts WHERE id = 'b4c5d6e7-f890-1234-bcde-f12345678901';

-- Hector Ordonez: Delete placeholder
DELETE FROM contacts WHERE id = 'bf2517f9-3d38-4d32-9370-0305675ca129';

-- Malcolm Hetzer: Keep +17068176088 (has 13 interactions), add other as secondary
UPDATE contacts 
SET secondary_phone = '+17068184015',
    notes = COALESCE(notes, '') || ' | Alt: +17068184015'
WHERE id = 'a0f3a2a5-ded8-4654-9066-55968bbc61c5';

DELETE FROM contacts WHERE id = '210eb45c-b2e1-4d0b-ab48-c2e7a00672b6';

-- Michael Strickland: Delete placeholder
DELETE FROM contacts WHERE id = 'a840ac87-3e34-42f6-bc40-b5943104bb15';

-- Zach Givens: Keep +17064241308 (has 12 interactions), delete placeholder
DELETE FROM contacts WHERE id = '47e533f7-479d-4e75-808a-929b779df847';
;
