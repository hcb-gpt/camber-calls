
-- More trade-specific vendors from VCF

-- Brandon Plumber
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Brandon (Plumber)',
    '+17062555147',
    'Plumber',
    'From VCF.',
    'vendor',
    'Plumbing'
);

-- Thomas HVAC
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Thomas (HVAC)',
    '+19122488300',
    'HVAC',
    'From VCF.',
    'vendor',
    'HVAC'
);

-- Rodney Peppers - Peppers HVAC
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Rodney Peppers',
    'Peppers HVAC',
    '+17709402211',
    'Owner',
    'Related to Peppers Heating & Air. From VCF.',
    'vendor',
    'HVAC'
);

-- Donald - Apalachee Air
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Donald (Apalachee Air)',
    'Apalachee Air',
    '+16789943735',
    'From VCF.',
    'vendor',
    'HVAC'
);

-- Dylan Whitmire - Air Georgia
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Dylan Whitmire',
    'Air Georgia',
    '+17705484265',
    'From VCF. Works with Austin Atkinson.',
    'vendor',
    'HVAC'
);

-- Roofing contacts
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Kirk (RWN Roofing)',
    'RWN Roofing',
    '+17066141094',
    'From VCF.',
    'vendor',
    'Roofing'
);

INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Tony Paulk',
    'Paulk Roofing',
    '+14045978622',
    'Cell. Office: +17702679453. From VCF.',
    'vendor',
    'Roofing'
);

INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Jacinto (Roofer)',
    '+17705277814',
    'Roofer',
    'From VCF.',
    'vendor',
    'Roofing'
);

-- Gutters
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Rodrigo (Gutters)',
    '+16789434290',
    'Gutters',
    'From VCF.',
    'vendor',
    'Gutters'
);

-- Select Door
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Skylar (Select Door)',
    'Select Door',
    '+17708463595',
    'From VCF.',
    'vendor',
    'Doors'
);

-- Waterproofing scheduling line
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Scheduling (Waterproofing)',
    'The Waterproofing Group',
    '+16787306385',
    'Scheduling line. From VCF.',
    'vendor',
    'Waterproofing'
);

-- Jacob Peters - Pasco (flow testing) - add missing role
UPDATE contacts SET 
    role = 'Sales Manager',
    notes = COALESCE(notes, '') || ' | Plumbing flow testing'
WHERE name = 'Jacob Peters' AND company LIKE '%Pasco%';
;
