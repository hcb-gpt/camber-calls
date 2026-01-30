-- Populate company_aliases with common variations (without LLC, Inc, etc.)

-- Internal staff - all HCB
UPDATE contacts SET company_aliases = ARRAY['Heartwood', 'HCB', 'Heartwood Builders', 'Heartwood Custom']
WHERE company = 'Heartwood Custom Builders';

-- Crossed Chisels (Cottrells)
UPDATE contacts SET company_aliases = ARRAY['Crossed Chisels', 'Crossed Chisels LLC', 'CC']
WHERE name = 'Alicia Cottrell';

UPDATE contacts SET company_aliases = ARRAY['Crossed Chisels', 'Crossed Chisels LLC', 'CC']  
WHERE name = 'Anthony Cottrell';

-- Hetzer Electric variations
UPDATE contacts SET company_aliases = ARRAY['Hetzer Electric', 'Hetzer', 'Hetzer Electric Company']
WHERE name = 'Malcolm Hetzer';

UPDATE contacts SET company_aliases = ARRAY['Hetzer Electric', 'Hetzer']
WHERE name = 'Taylor Messer';

-- Peppers HVAC
UPDATE contacts SET company_aliases = ARRAY['Peppers', 'Peppers Heating', 'Peppers Air', 'Peppers HVAC']
WHERE name = 'Gatlin';

-- Grounded Siteworks
UPDATE contacts SET company_aliases = ARRAY['Grounded', 'Grounded Siteworks']
WHERE name = 'Taylor Shannon';

-- Carter Lumber (two contacts)
UPDATE contacts SET company_aliases = ARRAY['Carter Lumber', 'Carter']
WHERE name IN ('Flynt Treadaway', 'Hector Ordonez');

-- Georgia Kitchens
UPDATE contacts SET company_aliases = ARRAY['Georgia Kitchens', 'GK', 'GA Kitchens']
WHERE name = 'Joe Laboon III';

-- Air Georgia
UPDATE contacts SET company_aliases = ARRAY['Air Georgia', 'Air Georgia Heating', 'AG Heating']
WHERE name = 'Austin Atkinson';

-- Mayne Tile
UPDATE contacts SET company_aliases = ARRAY['Mayne Tile', 'Mayne']
WHERE name = 'Bill Mayne';

-- Structuremen
UPDATE contacts SET company_aliases = ARRAY['Structuremen', 'Structure Men']
WHERE name = 'Brian Dove';

-- Georgia Insulation  
UPDATE contacts SET company_aliases = ARRAY['Georgia Insulation', 'GA Insulation']
WHERE name = 'Calvin Taylor';

-- Braswell Construction
UPDATE contacts SET company_aliases = ARRAY['Braswell', 'Braswell Construction', 'BCG']
WHERE name = 'Chris Gaugler';

-- Jayco Innovations
UPDATE contacts SET company_aliases = ARRAY['Jayco', 'Jayco Innovations']
WHERE name = 'Jose (Tony) Araujo';

-- Mobley Flooring
UPDATE contacts SET company_aliases = ARRAY['Mobley Flooring', 'Mobley']
WHERE name = 'Josh Mobley';

-- J&R Masonry
UPDATE contacts SET company_aliases = ARRAY['J&R Masonry', 'JR Masonry', 'J and R Masonry', 'J & R']
WHERE name = 'Luis Juarez';

-- Southeastern Sitecast
UPDATE contacts SET company_aliases = ARRAY['Southeastern Sitecast', 'SE Sitecast', 'Sitecast']
WHERE name = 'Michael Strickland';

-- Bryan's Plumbing  
UPDATE contacts SET company_aliases = ARRAY['Bryans Plumbing', 'Bryan Plumbing', 'Bryans Home Repair', 'Bryan Home Repair']
WHERE name = 'Randy Bryan';

-- T&J Vinyl
UPDATE contacts SET company_aliases = ARRAY['T&J Vinyl', 'TJ Vinyl', 'T and J Vinyl', 'T&J']
WHERE name = 'Tracy Postin';

-- Givens Landscaping
UPDATE contacts SET company_aliases = ARRAY['Givens Landscaping', 'Givens Irrigation', 'Givens']
WHERE name = 'Zach Givens';

-- Select Floors
UPDATE contacts SET company_aliases = ARRAY['Select Floors', 'Select']
WHERE name = 'Alexander Nasr';

-- Client companies
UPDATE contacts SET company_aliases = ARRAY['Weaver and Woodbery', 'Weaver & Woodbery', 'W&W']
WHERE name = 'David Woodbery';

UPDATE contacts SET company_aliases = ARRAY['Shiplify']
WHERE name = 'Blanton Winship';
;
