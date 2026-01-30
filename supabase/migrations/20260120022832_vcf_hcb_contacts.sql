
-- HCB-related contacts from VCF: clients, carpenters, team

-- Julie Skelton/Faulk (client) - update if exists
UPDATE contacts SET 
    email = 'faulkfive@gmail.com',
    notes = COALESCE(notes, '') || ' | Also known as Julie Faulk'
WHERE name LIKE '%Julie%Skelton%' OR name LIKE '%Julie%Faulk%';

-- Insert if not exists
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
SELECT 'Julie Skelton', 'Heartwood Custom Builders', '+17705979943', 'faulkfive@gmail.com', 'Client', '743 Hunter St, Madison, GA 30650. From VCF.', 'client'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17705979943');

-- William Lamb (client)
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
SELECT 'William Lamb', 'Heartwood Custom Builders', '+14044017599', 'Client', 'From VCF.', 'client'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14044017599');

-- Debi Lamb (client)
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
SELECT 'Debi Lamb', 'Heartwood Custom Builders', '+14045397868', 'Client', 'From VCF.', 'client'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14045397868');

-- Andie Vaughn (client)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
SELECT 'Andie Vaughn', 'Heartwood Custom Builders', '+17064246663', 'vaughnandie@gmail.com', 'Client', 'From VCF.', 'client'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17064246663');

-- Aleah Homer (owner related)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
SELECT 'Aleah Homer', 'Heartwood Custom Builders', '+13158687465', 'aleah.homer@yahoo.com', 'Owner', 'From VCF.', 'internal'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+13158687465');

-- Conner Hewell
INSERT INTO contacts (name, company, phone, notes, contact_type)
SELECT 'Conner Hewell', 'Heartwood Custom Homes', '+14706235369', 'From VCF.', 'internal'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14706235369');

-- Daniel Napier (carpenter)
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
SELECT 'Daniel Napier', 'Heartwood Custom Builders', '+17062407305', 'Carpenter', 'From VCF.', 'internal', 'Carpentry'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17062407305');

-- Edenilson/Eden Quevedo (carpenter)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
SELECT 'Eden Quevedo', 'Heartwood Custom Builders', '+14704692665', 'edenilsonrivasq17@gmail.com', 'Carpenter', 'Full name: Edenilson A Rivas Quevedo. From VCF.', 'internal', 'Carpentry'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+14704692665');

-- David Carter (carpenter)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
SELECT 'David Carter', 'Heartwood Custom Builders', '+17063192812', 'dlcjr0987@gmail.com', 'Carpenter', 'From VCF.', 'internal', 'Carpentry'
WHERE NOT EXISTS (SELECT 1 FROM contacts WHERE phone = '+17063192812');

-- Update client emails
UPDATE contacts SET email = 'louwinship@icloud.com'
WHERE name = 'Lou Winship' AND email IS NULL;

UPDATE contacts SET email = 'shayelyn@me.com'
WHERE name = 'Shayelyn Woodbery' AND email IS NULL;

UPDATE contacts SET email = 'shane.boyer@frcemail.com'
WHERE name = 'Shane Boyer' AND email IS NULL;

UPDATE contacts SET email = 'gmelling321@gmail.com'
WHERE name = 'Ginny Mellinger' AND email IS NULL;

UPDATE contacts SET email = 'emilysboyer@hotmail.com'
WHERE name = 'Emily Boyer' AND email IS NULL;

UPDATE contacts SET email = 'mikek@jdrcompany.com'
WHERE name = 'Mike Kreikemeier' AND email IS NULL;

UPDATE contacts SET email = 'blantoncwsr@shiplify.com'
WHERE name = 'Blanton Winship' AND email IS NULL;

UPDATE contacts SET email = 'permar_s@yahoo.com'
WHERE name = 'Steven Permar' AND email IS NULL;

UPDATE contacts SET email = 'debbie.permar@gmail.com'
WHERE name = 'Debbie Permar' AND email IS NULL;
;
