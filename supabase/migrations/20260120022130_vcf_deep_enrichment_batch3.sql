
-- Deep VCF Enrichment Batch 3: Update existing contacts with emails/phones

-- Update Chris Gaugler with secondary phone
UPDATE contacts SET 
    secondary_phone = '+16782832551',
    notes = COALESCE(notes, '') || ' | Company: +16782832551'
WHERE name = 'Chris Gaugler' AND phone = '+16782238966';

-- Update Frank Layson with all phones
UPDATE contacts SET 
    secondary_phone = '+14042608537',
    notes = COALESCE(notes, '') || ' | Third phone: +14043939919'
WHERE name = 'Frank Layson' AND secondary_phone IS NULL;

-- Update Michelle Braswell with secondary phone
UPDATE contacts SET 
    secondary_phone = '+17708835846',
    email = 'michelle@braswellconstructiongroup.com',
    role = 'Chief Operating Officer',
    notes = COALESCE(notes, '') || ' | Personal: +17708835846'
WHERE name LIKE '%Michelle%Bird%' OR (company ILIKE '%braswell%' AND name ILIKE '%michelle%');

-- Add Michelle Bird as separate contact (COO at Braswell)
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'Michelle Bird',
    'Braswell Construction Group, Inc.',
    '+16786254146',
    '+16782832551',
    'michelle@braswellconstructiongroup.com',
    'Chief Operating Officer',
    'From VCF.',
    'vendor'
) ON CONFLICT DO NOTHING;

-- Carter Lumber contacts updates
-- Christy Yancey - EWP Design Manager
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Christy Yancey',
    'Carter Lumber',
    '+16782831430',
    'christy.yancey@carterlumber.com',
    'EWP Design Manager',
    'From VCF.',
    'vendor',
    'Lumber'
);

-- Steven Young - EWP Designer at Carter
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Steven Young (Carter)',
    'Carter Lumber',
    '+17705309867',
    'steven.young@carterlumber.com',
    'EWP Designer',
    'From VCF. Works with Christy Yancey.',
    'vendor',
    'Lumber'
);

-- Natasha Smith - Carter Lumber Outside Sales
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Natasha Smith',
    'Carter Lumber',
    '+17708675000',
    'natasha.smith@carterlumber.com',
    'Outside Sales Coordinator',
    'From VCF.',
    'vendor',
    'Lumber'
);

-- Denise Denmark-Pinckney - Carter Lumber Collections
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Denise Denmark-Pinckney',
    'Carter Lumber',
    '+13308125608',
    'denise.pinckney@carterlumber.com',
    'Market Collections Manager',
    'From VCF.',
    'vendor',
    'Lumber'
);

-- Ilean Nelson - Carter Lumber Collections
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Ilean Nelson',
    'Carter Lumber',
    '+13309031907',
    'ilean.nelson@carterlumber.com',
    'Market Collection Manager',
    'From VCF.',
    'vendor',
    'Lumber'
);

-- Insurance contacts
-- Zach Henley - Oakbridge Insurance
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Zach Henley',
    'Oakbridge Insurance (Homebuilders Program)',
    '+16788235357',
    'zhenley@oakbridgeinsurance.com',
    'Account Executive',
    'From VCF.',
    'other'
);

-- Kristy Lambeth - Oakbridge Insurance
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Kristy Lambeth',
    'Oakbridge Insurance',
    '+17062214566',
    'klambeth@oakbridgeinsurance.com',
    'Account Manager',
    'From VCF.',
    'other'
);

-- Rachel Anderson - Oakbridge Insurance
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Rachel Anderson',
    'Oakbridge Insurance',
    '+17703570023',
    'randerson@oakbridgeinsurance.com',
    'Account Manager Assistant',
    'From VCF.',
    'other'
);

-- Marlena Tootle - Oakbridge Insurance
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Marlena Tootle',
    'Oakbridge Insurance',
    '+17703570038',
    'mtootle@oakbridgeinsurance.com',
    'Account Manager',
    'From VCF.',
    'other'
);

-- David Goddard - Bass Underwriters
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'David Goddard',
    'Bass Underwriters',
    '+16787139685',
    '+17705101614',
    'dgoddard@bassuw.com',
    'Senior Broker',
    'From VCF.',
    'other'
);

-- Lee Abney - Attorney
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Lee Abney',
    'Lambert, Reitman and Abney, L.L.C.',
    '+17063423566',
    'lma@lralaw.com',
    'Attorney',
    'From VCF.',
    'other'
);

-- Jennifer Callaway - Attorney
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Jennifer Callaway',
    'QHTL Law',
    '+17065437777',
    'jen@qhtllaw.com',
    'Attorney',
    'From VCF.',
    'other'
);
;
