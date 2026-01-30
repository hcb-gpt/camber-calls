
-- Deep VCF Enrichment Batch 7: Update existing contacts with missing data

-- Daniel Napier - Carpenter at Heartwood (internal team)
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Daniel Napier',
    'Heartwood Custom Builders',
    '+17062407305',
    'Carpenter',
    'HCB crew. From VCF.',
    'internal'
) ON CONFLICT DO NOTHING;

-- Update Daniel Martuscello with email
UPDATE contacts SET 
    email = 'dmartuscello@rentile.com',
    role = 'Design Consultant'
WHERE name = 'Daniel Martuscello' AND email IS NULL;

-- Update Malcolm Hetzer with email
UPDATE contacts SET email = 'malcolmhetzer4@gmail.com'
WHERE name = 'Malcolm Hetzer' AND email IS NULL;

-- Edenilson Rivas Quevedo - Carpenter at Heartwood
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Edenilson Rivas Quevedo',
    'Heartwood Custom Builders',
    '+14704692665',
    'edenilsonrivasq17@gmail.com',
    'Carpenter',
    'HCB crew. Also known as Eden. From VCF.',
    'internal'
) ON CONFLICT DO NOTHING;

-- David Carter - Carpenter at Heartwood
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'David Carter',
    'Heartwood Custom Builders',
    '+17063192812',
    'dlcjr0987@gmail.com',
    'Carpenter',
    'HCB crew. From VCF.',
    'internal'
) ON CONFLICT DO NOTHING;

-- Update existing vendor contacts with trade classifications
UPDATE contacts SET trade = 'Tile' WHERE name = 'Daniel Martuscello' AND trade IS NULL;
UPDATE contacts SET trade = 'Electrical' WHERE company ILIKE '%hetzer%' AND trade IS NULL;
UPDATE contacts SET trade = 'Masonry/Brick' WHERE company ILIKE '%j%j brick%' AND trade IS NULL;
UPDATE contacts SET trade = 'Architecture' WHERE name = 'Jim Bramlett' AND trade IS NULL;

-- Michelle Champagne Bramlett (Jim's wife?)
INSERT INTO contacts (name, phone, notes, contact_type)
VALUES (
    'Michelle Bramlett',
    '+14782939978',
    'Possibly related to Jim Bramlett (Foothills Architecture). From VCF.',
    'other'
) ON CONFLICT DO NOTHING;

-- Daniel Cantero
INSERT INTO contacts (name, phone, notes, contact_type)
VALUES (
    'Daniel Cantero',
    '+17702622523',
    'From VCF.',
    'other'
) ON CONFLICT DO NOTHING;

-- Geoff Calhoun - House Electric (update with email only since no phone)
UPDATE contacts SET email = 'geoff@houseelectricathens.com'
WHERE name = 'Geoff Calhoun' AND email IS NULL;

-- Add notes about J&J Brick office contacts
UPDATE contacts SET 
    notes = COALESCE(notes, '') || ' | Office: tweeann@jandjbrickandmaterials.com | Pat: +17705008023'
WHERE name = 'John Singleton' AND notes NOT LIKE '%tweeann%';
;
