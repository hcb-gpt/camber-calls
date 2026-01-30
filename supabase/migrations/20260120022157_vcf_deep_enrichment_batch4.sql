
-- Deep VCF Enrichment Batch 4: More vendors and services

-- Pasco LLC contacts (flow testing)
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type, trade)
VALUES (
    'Rick Mill',
    'Pasco, LLC',
    '+18035182972',
    '+14707820082',
    'rick.mill@pasco-llc.us',
    'President',
    'Flow testing. Office: +16783429499. From VCF.',
    'vendor',
    'Testing/Inspection'
);

INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type, trade)
VALUES (
    'Matt Parsons',
    'Pasco, LLC',
    '+14045206322',
    '+14707820086',
    'matt.parsons@pasco-llc.us',
    'Branch Manager',
    'Flow testing. Office: +16783429499. From VCF.',
    'vendor',
    'Testing/Inspection'
);

INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Destiny Gee',
    'Pasco, LLC',
    '+14707820078',
    'destiny.gee@pasco-llc.us',
    'Office Manager',
    'Flow testing. Office: +16783429499. From VCF.',
    'vendor',
    'Testing/Inspection'
);

-- Waterproofing Group contacts
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Lindsay (Waterproofing)',
    'The Waterproofing Group',
    '+16782234948',
    'Scheduling',
    'From VCF.',
    'vendor',
    'Waterproofing'
);

INSERT INTO contacts (name, company, phone, secondary_phone, role, notes, contact_type, trade)
VALUES (
    'Justin (Waterproofing)',
    'The Waterproofing Group',
    '+16787206414',
    '+14707652123',
    'Engineer',
    'From VCF.',
    'vendor',
    'Waterproofing'
);

-- Buildertrend contact
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Emilia Bradford',
    'Buildertrend',
    '+15313656697',
    'emilia.bradford@buildertrend.com',
    'Setup Manager',
    'From VCF.',
    'other'
);

-- CoConstruct contact (competitor but useful)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Carli Tornetta',
    'CoConstruct',
    '+14342708387',
    'ctornetta@coconstruct.com',
    'Customer Migration Manager',
    'From VCF.',
    'other'
);

-- Victoria Sorone - Adaptive (construction software)
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'Victoria Sorone',
    'Adaptive',
    '+17153796903',
    '+19529002243',
    'victoria@adaptive.build',
    'Midwest Representative',
    'Construction software. From VCF.',
    'other'
);

-- Simone Martin - Junction Agency (real estate?)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Simone Martin',
    'The Junction Agency',
    '+17064863208',
    'simone@thejunctionagency.com',
    'Agent',
    'From VCF.',
    'other'
);

-- Taylor Duke - Danlar Lighting
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type, trade)
VALUES (
    'Taylor Duke',
    'Danlar Lighting',
    '+17704832877',
    '+17702789702',
    'tduke@danlarlighting.com',
    'Sales',
    'From VCF.',
    'vendor',
    'Lighting'
);

-- Brandi Smith - Grounded Siteworks Office Manager
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Brandi Smith',
    'Grounded Siteworks, LLC',
    '+17068188198',
    'Office Manager',
    'Works with Taylor Shannon. From VCF.',
    'vendor',
    'Sitework'
);

-- American Stalls contact
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'Madeleine Friend',
    'American Stalls',
    '+17037282454',
    '+18559578255',
    'mfriend@americanstalls.com',
    'Senior Project Manager',
    'Horse stalls/equine equipment. From VCF.',
    'vendor'
);

-- Adam Sbaiti - Select Floors (update existing)
UPDATE contacts SET 
    secondary_phone = '+17702183462',
    notes = COALESCE(notes, '') || ' | Cell: +17702183462'
WHERE name LIKE '%Adam%' AND company ILIKE '%select floor%';

-- Update Brian Dove with email
UPDATE contacts SET email = 'bkdove@me.com'
WHERE name = 'Brian Dove' AND email IS NULL;

-- Update Wayman Bryan with company
UPDATE contacts SET 
    company = 'Septic Services',
    trade = 'Septic'
WHERE name = 'Wayman Bryan' AND company IS NULL;

-- Dave's Appliance Warehouse
INSERT INTO contacts (name, company, phone, secondary_phone, email, notes, contact_type, trade)
VALUES (
    'David Craver',
    'Dave''s Appliance Warehouse',
    '+16787267039',
    '+12298693487',
    'davesapplianceoutsidesales@gmail.com',
    'Appliance warehouse. From VCF.',
    'vendor',
    'Appliances'
);

-- Terry Brock - Sawmill
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Terry Brock',
    'Brock''s Sawmill',
    '+16782316598',
    'Sawmill. From VCF.',
    'vendor',
    'Lumber'
);

-- Preferred Roll-Off
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Preferred Roll-Off',
    'Preferred Roll-Off',
    '+17707871936',
    'Dumpster service. From VCF.',
    'vendor'
);
;
