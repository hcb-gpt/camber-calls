
-- Deep VCF Enrichment Batch 1: New vendor contacts

-- Tawney Patterson - PDI (we have but missing role details)
UPDATE contacts SET 
    role = 'Senior Showroom Consultant',
    email = 'tpatterson@relyonpdi.com',
    phone = '+17709639231'
WHERE name LIKE '%Tawney Patterson%';

-- Dave Terry - PDI (new contact)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Dave Terry',
    'PDI (Plumbing Distributors Inc)',
    '+14044233055',
    'dterry@relyonpdi.com',
    'Sales',
    'From VCF. Second PDI contact.',
    'vendor',
    'Plumbing Fixtures'
);

-- Clay Weldon - PDI (new contact)
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type, trade)
VALUES (
    'Clay Weldon',
    'PDI (Plumbing Distributors Inc)',
    '+17709105823',
    '+14043525003',
    'cweldon@relyonpdi.com',
    'Showroom Manager',
    'From VCF.',
    'vendor',
    'Plumbing Fixtures'
);

-- Casey Lobdell - Marvin Windows (new contact)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Casey Lobdell',
    'Marvin (Southeast)',
    '+14043020603',
    'caseylobdell@marvin.com',
    'Regional Manager Architectural Sales',
    'From VCF.',
    'vendor',
    'Windows/Doors'
);

-- Coleman Jones - Window Concepts (new contact)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Coleman Jones',
    'Window Concepts Ltd.',
    '+14782903261',
    'coleman@windowconcepts.com',
    'Sales Consultant',
    'From VCF. Works with Amy Champion.',
    'vendor',
    'Windows/Doors'
);

-- Blake Butcher - Concrete Craft (new contact)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Blake Butcher',
    'Concrete Craft',
    '+17063383062',
    'bs.decorative.concrete@gmail.com',
    'Owner',
    'Decorative concrete. From VCF.',
    'vendor',
    'Concrete'
);

-- Travis Shadburn - Cabinets (new contact)
INSERT INTO contacts (name, company, phone, secondary_phone, role, notes, contact_type, trade)
VALUES (
    'Travis Shadburn',
    'Shadburn Construction',
    '+17068654833',
    '+16783164117',
    'Cabinets',
    'Cabinet work. From VCF.',
    'vendor',
    'Cabinetry'
);

-- Chris Shannon - CLS Const (new contact)
INSERT INTO contacts (name, company, phone, email, notes, contact_type, trade)
VALUES (
    'Chris Shannon',
    'CLS Construction',
    '+16788581428',
    'cshannon01@gmail.com',
    'From VCF.',
    'vendor',
    'General Construction'
);

-- Jamie Stephens - Masonry (new contact)
INSERT INTO contacts (name, company, phone, email, notes, contact_type, trade)
VALUES (
    'Jamie Stephens',
    'James Stephens Masonry',
    '+17704806214',
    'jsmotorsports17@bellsouth.net',
    'From VCF.',
    'vendor',
    'Masonry'
);

-- Preston Satterfield - Schmidt and Satterfield (new contact)
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Preston Satterfield',
    'Schmidt And Satterfield',
    '+17063401777',
    'From VCF.',
    'vendor',
    'General Construction'
);

-- Lewis - Morgan County Inspector (new contact)
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Lewis (Morgan Co Inspector)',
    'Morgan County',
    '+17068181815',
    'Building Inspector',
    'Morgan County building inspector. From VCF.',
    'other'
);

-- Dennis Chapman - Electrician (new contact)
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Dennis Chapman',
    '+17062023290',
    'Electrician',
    'From VCF.',
    'vendor',
    'Electrical'
);

-- Santos Sr - Brick Mason Madison (new contact)
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Santos Sr',
    '+16782272668',
    'Brick Mason',
    'Madison area. From VCF.',
    'vendor',
    'Masonry/Brick'
);
;
