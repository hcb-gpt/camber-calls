
-- Deep VCF Enrichment Batch 8: Final contacts and address updates

-- Fred Kitchens - multiple phones
INSERT INTO contacts (name, phone, secondary_phone, notes, contact_type)
SELECT 
    'Fred Kitchens',
    '+17064842642',
    '+14042454061',
    'Third phone: +17067521687. From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17064842642');

-- Dr Blackmon
INSERT INTO contacts (name, phone, street, city, state, notes, contact_type)
SELECT 
    'Dr Blackmon',
    '+17065521700',
    '1305 Jennings Mill Rd',
    'Bogart',
    'GA',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17065521700');

-- Joseph Hurley (Bo Hurley's full name)
UPDATE contacts SET 
    street = '2401 Downs Creek Dr',
    city = 'Athens',
    state = 'GA',
    zip = '30606',
    phone = '+17709103997'
WHERE name = 'Bo Hurley';

-- Add secondary phone for Bo Hurley from VCF
UPDATE contacts SET secondary_phone = '+17709103997'
WHERE name = 'Bo Hurley' AND secondary_phone IS NULL;

-- Jason Bruce
INSERT INTO contacts (name, phone, street, city, state, notes, contact_type)
SELECT 
    'Jason Bruce',
    '+17068184094',
    '2021 Lower Apalachee Rd',
    'Madison',
    'GA',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17068184094');

-- Kathy Query
INSERT INTO contacts (name, phone, street, city, state, notes, contact_type)
SELECT 
    'Kathy Query',
    '+13379901251',
    '1491 Swords Trail',
    'Buckhead',
    'GA',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+13379901251');

-- Zach Massey
INSERT INTO contacts (name, phone, street, city, state, notes, contact_type)
SELECT 
    'Zach Massey',
    '+17064740435',
    '954 Saye Creek Dr',
    'Madison',
    'GA',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17064740435');

-- Bret Wahl
INSERT INTO contacts (name, phone, street, city, state, notes, contact_type)
SELECT 
    'Bret Wahl',
    '+19167693479',
    '1051 Greenwood Cir',
    'Madison',
    'GA',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+19167693479');

-- Update Julie Skelton/Faulk with address
UPDATE contacts SET 
    street = '743 Hunter St',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name LIKE '%Julie%' AND (name LIKE '%Skelton%' OR name LIKE '%Faulk%') AND street IS NULL;

-- Jody Higdon - Clerk of Superior Court
INSERT INTO contacts (name, company, phone, email, street, city, state, role, notes, contact_type)
SELECT 
    'Jody Higdon',
    'Clerk of Superior Court',
    '+17067076187',
    'jody.higdon@gsccca.org',
    '2701 Newborn Road',
    'Mansfield',
    'GA',
    'Clerk',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17067076187');

-- Update Frankie Slaughter with address
UPDATE contacts SET 
    street = '1121 Eatonton Rd',
    city = 'Madison',
    state = 'GA'
WHERE name LIKE '%Frankie Slaughter%' AND street IS NULL;

-- Thrifty Mac Pharmacy
INSERT INTO contacts (name, company, phone, street, city, state, notes, contact_type)
SELECT 
    'Thrifty Mac Pharmacy',
    'Thrifty Mac Pharmacy',
    '+17063424141',
    '218 S Main St',
    'Madison',
    'GA',
    'Pharmacy. From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17063424141');
;
