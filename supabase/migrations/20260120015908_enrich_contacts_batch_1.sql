
-- Enrichment from Gmail mining
-- Dwayne Brown - Accent Granite
UPDATE contacts SET 
  email = 'accentgranite@elberton.net',
  street = 'PO Box 182',
  city = 'Elberton',
  state = 'GA',
  zip = '30635'
WHERE name = 'Dwayne Brown' AND email IS NULL;

-- Danny Kreyman-Vaughn
UPDATE contacts SET 
  email = 'daniel.m.kreyman@gmail.com',
  role = 'Homeowner'
WHERE name = 'Danny Kreyman-Vaughn' AND email IS NULL;

-- Andie Kreyman-Vaughn - add role
UPDATE contacts SET 
  role = 'Homeowner'
WHERE name = 'Andie Kreyman-Vaughn' AND role IS NULL;

-- Melissa Robinson - Robinson Well Company
UPDATE contacts SET 
  email = 'robinsonwell2189@gmail.com',
  street = '2189 Monroe Jersey Rd',
  city = 'Monroe',
  state = 'GA',
  zip = '30655',
  role = 'Owner'
WHERE name = 'Melissa Robinson' AND email IS NULL;

-- Shannon Hudgins - Soil Profiles
UPDATE contacts SET 
  email = 'soilprofiles@gmail.com'
WHERE name = 'Shannon Hudgins' AND email IS NULL;

-- Ginny Mellinger - Client/Project Manager
UPDATE contacts SET 
  role = 'Homeowner/Project Rep',
  street = '2033 Spartan Ests Dr',
  city = 'Athens',
  state = 'GA'
WHERE name = 'Ginny Mellinger' AND role IS NULL;

-- Shane Boyer - address and role  
UPDATE contacts SET 
  street = '410 E Central Ave',
  city = 'Madison',
  state = 'GA',
  zip = '30650',
  role = 'Homeowner'
WHERE name = 'Shane Boyer';

-- Ginger Gray - add email
UPDATE contacts SET 
  email = 'ginger@alexsmithgardendesign.com'
WHERE name = 'Ginger Gray' AND email IS NULL;
;
