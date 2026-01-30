
-- More enrichments from Gmail mining

-- Air Georgia contacts - add service email
UPDATE contacts SET 
  email = 'service@air-ga.net'
WHERE name = 'Gatlin Hawkins' AND email IS NULL;

-- Hetzer Electric - Taylor Messer works there but Malcolm is owner
-- Add Malcolm Hetzer email to notes for Taylor
UPDATE contacts SET 
  notes = COALESCE(notes, '') || ' Company owner: Malcolm Hetzer (malcolmhetzer4@gmail.com)'
WHERE name = 'Taylor Messer' AND (notes IS NULL OR notes NOT LIKE '%Malcolm%');

-- Chris Skelton and Julie Skelton - homeowners
UPDATE contacts SET 
  role = 'Homeowner'
WHERE name IN ('Chris Skelton', 'Julie Skelton') AND role IS NULL;

-- Karly Moss - add role
UPDATE contacts SET 
  role = 'Homeowner'  
WHERE name = 'Karly Moss' AND role IS NULL;

-- Norma Young - add role (same address as Brian Young)
UPDATE contacts SET 
  role = 'Homeowner',
  street = '1101 Red Oak Ct',
  city = 'Watkinsville',
  state = 'GA'
WHERE name = 'Norma Young' AND role IS NULL;

-- Brian Young - confirm address
UPDATE contacts SET 
  street = '1101 Red Oak Ct',
  city = 'Watkinsville',
  state = 'GA'
WHERE name = 'Brian Young' AND street IS NULL;

-- Patty Layson - add role (Frank Layson's wife)
UPDATE contacts SET 
  role = 'Homeowner'
WHERE name = 'Patty Layson' AND role IS NULL;
;
