
-- Trade assignments from Chad's review

-- Temporary Facilities (porta potties, dumpsters, trash)
UPDATE contacts SET trade = 'Temporary Facilities' WHERE id IN (
  'ac484967-cdc9-4ec9-8c4a-649283913480', -- AAA Northside Portable
  'c7a0564d-2b93-430e-b489-1f0c056b1534', -- ASAP Portapotty
  '0413428d-2d60-41f1-9a77-4c28e7681fac', -- Classic City Trash
  '4e07d63d-728e-414d-a277-c4f8ed52d784'  -- Preferred Roll-Off
);

-- Equipment
UPDATE contacts SET trade = 'Equipment' WHERE id IN (
  '68588082-c056-4023-99d9-43be9bf9aaad', -- Ag Pro
  'd3bc6d3f-1864-456b-aeab-e0f27fc6928c'  -- Madison Rentals
);

-- Photography
UPDATE contacts SET trade = 'Photography' WHERE id IN (
  'b83beb42-5f36-4803-a453-9db387e67e43', -- Charlie Byers
  'ccb3ca89-05be-4ad8-9f44-7bea92c4aaf0'  -- Jay Bentley
);

-- Handyman
UPDATE contacts SET trade = 'Handyman' WHERE id IN (
  '9a8fe1b1-3ca1-4d86-b4df-595b6a609f00', -- Frankie Slaughter
  '3b5dc9e3-a60b-483f-acfd-821257b1d91e'  -- Marshal Davis
);

-- Roofing (Michelle Bird at Braswell)
UPDATE contacts SET trade = 'Roofing' WHERE id = '4a3f35cb-9c18-4be2-a9e3-8008086f6295';

-- Building Materials
UPDATE contacts SET trade = 'Building Materials' WHERE id = 'fc404e3f-20cf-472e-a4c9-b8464c142429'; -- Social Circle Ace

-- General Construction
UPDATE contacts SET trade = 'General Construction' WHERE id = 'ec3d45f8-ebb7-4404-a1f4-52fd01974413'; -- Matthew Knighton

-- Stone/Masonry (Lauren Poynter White - Fieldstone Center)
UPDATE contacts SET trade = 'Stone/Masonry' WHERE id = 'bc9bd233-9061-4a27-9c29-0fd6f46dd4f9';

-- Equine (new trade)
UPDATE contacts SET trade = 'Equine' WHERE id IN (
  'e8447c79-acda-411c-a4e7-4cbdfab1b9a0', -- Madeleine Friend (American Stalls)
  '1fc217d8-95c1-416a-9373-10ecee5dfbe3'  -- Marybeth Hopkins (Heritage Equine)
);

-- Equipment (Youngblood - small engine, tractor, dump trailer)
UPDATE contacts SET trade = 'Equipment' WHERE id = 'b5e35708-95ab-43ea-9503-c6142e5b67ae';

-- Cleaning (Miguel Lopez was already assigned but let's confirm)
UPDATE contacts SET trade = 'Cleaning' WHERE id = '0c626b96-b2d0-457a-b2e0-dc7b61d0ab0d';

-- Delete Jacob Eisele (Precision Approach - discarded per Chad)
DELETE FROM contacts WHERE id = '0e5bfb40-9980-46c4-9310-b50cd5625c8d';
;
