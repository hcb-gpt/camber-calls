
-- Add new contacts discovered in VCF files (phone required)

-- Joel Carroll - Carroll Pump & Well (well drilling vendor)
INSERT INTO contacts (name, company, phone, secondary_phone, role, notes, contact_type, trade)
VALUES (
    'Joel Carroll',
    'Carroll Pump & Well',
    '+17064850442',
    '+14789687555',
    NULL,
    'Well drilling. From VCF.',
    'vendor',
    'Well Drilling'
);

-- Pat - J&J Brick (additional contact)
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Pat (J&J Brick)',
    'J&J Brick and Materials Co., Inc.',
    '+17705008023',
    'From VCF.',
    'vendor',
    'Masonry/Brick'
);

-- Andrew Fagan - Electrician
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Andrew Fagan',
    '+17706534639',
    'Electrician',
    'From VCF.',
    'vendor',
    'Electrical'
);

-- Todd Peppers - HVAC (related to Peppers Heating)
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Todd Peppers',
    'Peppers Heating & Air',
    '+16789939806',
    'HVAC. Gatlin Hawkins formerly worked here. From VCF.',
    'vendor',
    'HVAC'
);

-- Update Larry Fitzgerald with company phone
UPDATE contacts SET notes = COALESCE(notes, '') || ' | Company phone: +17065579010'
WHERE name = 'Larry Fitzgerald';

-- Update John Singleton with email from VCF
UPDATE contacts SET email = 'brickman1@live.com'
WHERE name = 'John Singleton' AND email IS NULL;

-- Add Tweeann and Chelsea emails to John Singleton's notes (they're J&J Brick contacts)
UPDATE contacts SET notes = COALESCE(notes, '') || ' | Office: tweeann@jandjbrickandmaterials.com'
WHERE name = 'John Singleton';
;
