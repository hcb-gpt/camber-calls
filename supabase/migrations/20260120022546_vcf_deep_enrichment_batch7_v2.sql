
-- Deep VCF Enrichment Batch 7: Clients and carpenters (phone required)

-- William Lamb - Client
INSERT INTO contacts (name, phone, role, notes, contact_type)
VALUES (
    'William Lamb',
    '+14044017599',
    'Client',
    'Heartwood client. From VCF.',
    'client'
);

-- Debi Lamb - Client
INSERT INTO contacts (name, phone, role, notes, contact_type)
VALUES (
    'Debi Lamb',
    '+14045397868',
    'Client',
    'Heartwood client. From VCF.',
    'client'
);

-- Andie Vaughn - Client
INSERT INTO contacts (name, phone, email, role, notes, contact_type)
VALUES (
    'Andie Vaughn',
    '+17064246663',
    'vaughnandie@gmail.com',
    'Client',
    'Heartwood client. From VCF.',
    'client'
);

-- Daniel Napier - Carpenter
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Daniel Napier',
    'Heartwood Custom Builders',
    '+17062407305',
    'Carpenter',
    'HCB carpenter. From VCF.',
    'team',
    'Carpentry'
);

-- Edenilson Rivas Quevedo - Carpenter
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Edenilson Rivas Quevedo',
    'Heartwood Custom Builders',
    '+14704692665',
    'edenilsonrivasq17@gmail.com',
    'Carpenter',
    'HCB carpenter. From VCF.',
    'team',
    'Carpentry'
);

-- David Carter - Carpenter
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'David Carter',
    'Heartwood Custom Builders',
    '+17063192812',
    'dlcjr0987@gmail.com',
    'Carpenter',
    'HCB carpenter. From VCF.',
    'team',
    'Carpentry'
);

-- Conner Hewell - Heartwood Custom Homes
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Conner Hewell',
    'Heartwood Custom Homes',
    '+14706235369',
    'From VCF.',
    'other'
);

-- Aleah Homer - Owner (if not exists)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
SELECT 
    'Aleah Homer',
    'Heartwood Custom Builders',
    '+13158687465',
    'aleah.homer@yahoo.com',
    'Owner',
    'HCB owner. From VCF.',
    'team'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+13158687465');

-- Update Debbie Permar with email
UPDATE contacts SET email = 'debbie.permar@gmail.com'
WHERE name = 'Debbie Permar' AND email IS NULL;

-- Update Steven Permar with email
UPDATE contacts SET email = 'permar_s@yahoo.com'
WHERE name = 'Steven Permar' AND email IS NULL;

-- Update Hector Ordoñez with proper data
UPDATE contacts SET 
    email = 'hector.ordonez@carterlumber.com',
    role = 'Sales'
WHERE name LIKE '%Hector%' AND company ILIKE '%Carter%';

-- Chris Aranda - Innovative Flooring Group
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
SELECT 
    'Chris Aranda',
    'Innovative Flooring Group',
    '+14702342314',
    'Owner',
    'Flooring. From VCF.',
    'vendor',
    'Flooring'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14702342314');

-- Dave Miller - Lake Country Specialty Milling
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
SELECT 
    'Dave Miller',
    'Lake Country Specialty Milling',
    '+14047353427',
    'Owner',
    'Specialty milling. From VCF.',
    'vendor',
    'Millwork'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14047353427');

-- Nellie Cheek
INSERT INTO contacts (name, phone, email, role, notes, contact_type)
SELECT 
    'Nellie Cheek',
    '+19109646846',
    'nelpage.nc@gmail.com',
    'Owner',
    'From VCF.',
    'other'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+19109646846');
;
