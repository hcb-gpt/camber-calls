
-- Deep VCF Enrichment Batch 6: More specialty vendors

-- Rob Gas Guy
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Rob (Gas Guy)',
    '+17068190985',
    'Gas Line',
    'From VCF.',
    'vendor',
    'Gas/Plumbing'
);

-- Baltozar Siding
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Baltozar (Siding)',
    '+14044066383',
    'Siding',
    'From VCF.',
    'vendor',
    'Siding'
);

-- German Siding
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'German (Siding)',
    '+14045533359',
    'Siding',
    'From VCF.',
    'vendor',
    'Siding'
);

-- Miguel Siding
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Miguel (Siding)',
    '+14044216673',
    'Siding',
    'From VCF.',
    'vendor',
    'Siding'
);

-- Rodrigo Gutters
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Rodrigo (Gutters)',
    '+16789434290',
    'Gutters',
    'From VCF.',
    'vendor',
    'Gutters'
);

-- Phillip Alarm
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Phillip (Alarm)',
    '+17062020781',
    'Alarm/Security',
    'From VCF.',
    'vendor',
    'Security'
);

-- Jeremy Moon Grading
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Jeremy Moon',
    '+17707157988',
    'Grading',
    'From VCF.',
    'vendor',
    'Sitework'
);

-- Dave Wood Salvage
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Dave (Wood Salvage)',
    '+13157238951',
    'Salvage',
    'Wood salvage. From VCF.',
    'vendor',
    'Lumber'
);

-- Brian Willingham Millwork
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Brian Willingham',
    '+14788080438',
    'Millwork',
    'From VCF.',
    'vendor',
    'Millwork'
);

-- Zachary Trim Helper Madison
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Zachary (Trim Helper)',
    '+16783277257',
    'Trim Carpenter',
    'Madison area. From VCF.',
    'vendor',
    'Carpentry'
);

-- Rob Gratis DRYWALL
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Rob Gratis',
    '+14047877174',
    'Drywall',
    'From VCF.',
    'vendor',
    'Drywall'
);

-- Bonnie Drywall
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Bonnie (Drywall)',
    '+17067130054',
    'Drywall',
    'From VCF.',
    'vendor',
    'Drywall'
);

-- Update Jimmy Chastain with email if exists
UPDATE contacts SET email = 'chastainjj0@gmail.com'
WHERE name = 'Jimmy Chastain' AND email IS NULL;

-- Shannon Hudgins - Soil Profiles
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Shannon Hudgins',
    'Soil Profiles, Inc.',
    '+17708429895',
    'Soil Scientist',
    'Athens area. From VCF.',
    'vendor',
    'Septic'
);

-- John Kopec - John Willis Homes
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'John Kopec',
    'John Willis Homes',
    '+17706231496',
    'johnk@johnwilliscustomhomes.com',
    'Project Manager',
    'Custom home builder. From VCF.',
    'other'
);

-- Garry Phelps - Welding/Radiator
UPDATE contacts SET role = 'Owner'
WHERE name LIKE '%Phelps%' AND company LIKE '%Welding%';
;
