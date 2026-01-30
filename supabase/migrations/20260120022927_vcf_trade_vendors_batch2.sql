
-- More trade vendors from VCF

-- Phillip Alarm
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Phillip (Alarm)',
    '+17062020781',
    'Alarm',
    'From VCF.',
    'vendor',
    'Security'
);

-- Drywall contacts
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Rob Gratis',
    '+14047877174',
    'Drywall',
    'From VCF.',
    'vendor',
    'Drywall'
);

INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Bonnie (Drywall)',
    '+17067130054',
    'Drywall',
    'From VCF.',
    'vendor',
    'Drywall'
);

-- Framers
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Salvador (Framer)',
    '+16786565463',
    'Framer',
    'From VCF.',
    'vendor',
    'Framing'
);

INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Sergio (Framer)',
    '+16789271339',
    'Framer',
    'Works with Dove. From VCF.',
    'vendor',
    'Framing'
);

INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Johnny O''Kelly',
    '+17705604769',
    'Framer',
    'From VCF.',
    'vendor',
    'Framing'
);

-- Hardscape
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Mike Fournier',
    '+12394500439',
    'Hardscape',
    'From VCF.',
    'vendor',
    'Hardscape'
);

-- Glass/Mirror
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Clark Glass & Mirror',
    'Clark Glass & Mirror',
    '+17065495145',
    'From VCF.',
    'vendor',
    'Glass'
);

INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Austin (Atlanta Glass)',
    'Atlanta Glass And Mirror',
    '+17705477768',
    'From VCF.',
    'vendor',
    'Glass'
);

-- Stacey Fireplace already exists, update with trade
UPDATE contacts SET trade = 'Fireplace'
WHERE name ILIKE '%Stacey%' AND phone = '+17068183679';

-- Update John David Window Concepts (already added but confirm company)
UPDATE contacts SET company = 'Window Concepts Ltd.'
WHERE name = 'John David' AND phone = '+17065901850';
;
