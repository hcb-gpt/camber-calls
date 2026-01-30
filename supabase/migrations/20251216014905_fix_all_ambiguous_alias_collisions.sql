-- Fix alias collisions by removing/adjusting ambiguous aliases

-- SAME HOUSEHOLD (acceptable collisions - surname shared intentionally):
-- Hurley (Bo + Kaylen) - KEEP: They're married, "Hurley" can mean either
-- Winship (Lou + Blanton) - KEEP: They're married, context usually clarifies  
-- Woodbery (David + Shayelyn) - KEEP: They're married
-- Cottrell (Anthony + Alicia) - KEEP: Same company, business context

-- SAME PERSON (acceptable - just two contact records):
-- Zack Sittler internal vs personal - KEEP: Same person, different phones

-- PROBLEMATIC COLLISIONS TO FIX:

-- 1. "Taylor" - Two different people in different roles
UPDATE contacts 
SET aliases = array_remove(aliases, 'Taylor')
WHERE name = 'Taylor Messer';
-- Taylor Shannon keeps "Taylor" since they're primary sitework vendor

UPDATE contacts 
SET aliases = array_remove(aliases, 'Taylor')
WHERE name = 'Taylor Shannon';
-- Actually remove from both - use full names

-- 2. "Brian" - Two different people  
UPDATE contacts 
SET aliases = ARRAY['Brian Young', 'B Young']
WHERE name = 'Brian Young';

UPDATE contacts 
SET aliases = ARRAY['Brian Dove', 'Structuremen', 'B Dove']
WHERE name = 'Brian Dove';

-- 3. "Zach" collision with Zach Givens
UPDATE contacts 
SET aliases = array_remove(aliases, 'Zach')
WHERE name = 'Zack Sittler' AND contact_type = 'internal';
-- Zack uses "Zack" not "Zach" typically

UPDATE contacts 
SET aliases = ARRAY['Zach Givens', 'Givens Landscaping', 'Givens Irrigation', 'Z Givens']
WHERE name = 'Zach Givens';

-- 4. "Hetzer Electric" - two people at same company
-- Malcolm is the owner, Taylor is a tech - keep for Malcolm only
UPDATE contacts 
SET aliases = array_remove(aliases, 'Hetzer Electric')
WHERE name = 'Taylor Messer';

UPDATE contacts 
SET aliases = ARRAY['Taylor Messer', 'T Messer']
WHERE name = 'Taylor Messer';

-- 5. "A Cottrell" - ambiguous initial, remove from both
UPDATE contacts 
SET aliases = ARRAY['Alicia', 'Alicia Cottrell', 'Crossed Chisels', 'Cottrell']
WHERE name = 'Alicia Cottrell';

UPDATE contacts 
SET aliases = ARRAY['Anthony', 'Anthony Cottrell', 'Tony Cottrell', 'Crossed Chisels LLC', 'Cottrell']
WHERE name = 'Anthony Cottrell';

-- 6. Remove single-letter "Z" - too ambiguous
UPDATE contacts 
SET aliases = array_remove(aliases, 'Z')
WHERE 'Z' = ANY(aliases);
;
