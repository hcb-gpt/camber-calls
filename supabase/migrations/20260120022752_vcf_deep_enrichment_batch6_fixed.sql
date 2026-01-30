
-- Deep VCF Enrichment Batch 6: Rentals, portables, local services (fixed)

-- Madison Rentals
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Madison Rentals',
    'Madison Rentals',
    '+17063428665',
    'Equipment rental. From VCF.',
    'vendor'
);

-- Portable toilet services
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'ASAP Portapotty',
    'ASAP Portapotty',
    '+17065492727',
    'Athens area. From VCF.',
    'vendor'
);

INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'AAA Northside Portable',
    'AAA Northside Portable Toilets',
    '+14784526936',
    'Milledgeville area. From VCF.',
    'vendor'
);

-- Social Circle Ace
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Social Circle Ace',
    'Social Circle Ace Home Center',
    '+17704643354',
    '181 S Cherokee Rd, Social Circle, GA 30025. From VCF.',
    'vendor',
    'Building Materials'
);

-- Champion Lumber
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Champion Lumber',
    'Champion Lumber',
    '+17064686518',
    'From VCF.',
    'vendor',
    'Lumber'
);

-- Ag Pro
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Ag Pro',
    'Ag Pro',
    '+17063422332',
    'From VCF.',
    'vendor'
);

-- Youngblood Service
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Youngblood Service',
    'Youngblood Service Department',
    '+17063422242',
    'From VCF.',
    'vendor'
);

-- Lowe's Pro Desk Athens
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Lowes Pro Desk Athens',
    'Lowes Pro',
    '+17065406684',
    'Athens GA. From VCF.',
    'vendor',
    'Building Materials'
);

-- Andrew Johnson - Lowe's Pro Account Manager
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Andrew Johnson',
    'Lowes Pro',
    '+19432270462',
    'Pro Account Manager',
    'From VCF.',
    'vendor',
    'Building Materials'
);

-- Real Estate Photography (with company to satisfy constraint)
INSERT INTO contacts (name, company, phone, secondary_phone, role, notes, contact_type)
VALUES (
    'Jay Bentley',
    'Jay Bentley Media',
    '+14782341444',
    '+16782098787',
    'Photographer',
    'Real estate photography. From VCF.',
    'vendor'
);

INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Charlie Byers',
    'Real Estate Photography',
    '+16789006204',
    'From VCF.',
    'vendor'
);

-- Cleaning (with trade)
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Angie Sanders',
    '+16787945746',
    'Cleaning',
    'Madison area. From VCF.',
    'vendor',
    'Cleaning'
);

INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Miguel Lopez',
    'Family Pro Cleaning',
    '+17065082511',
    'From VCF.',
    'vendor',
    'Cleaning'
);

-- City of Madison utilities
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'Kee Kee Hunnicutt',
    'City of Madison',
    '+17063423454',
    '+17063421251',
    'khunnichtt@madisonga.com',
    'Supervisor, Utility Billing',
    'From VCF.',
    'other'
);

INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Adam Bates',
    'City of Madison',
    '+17063184201',
    'Gas Hookup',
    'From VCF.',
    'other'
);

-- Jody Higdon - Clerk of Superior Court
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Jody Higdon',
    'Clerk of Superior Court',
    '+17077076187',
    'jody.higdon@gsccca.org',
    'Clerk',
    'From VCF.',
    'other'
);

-- Katie Stinnett - Georgia Insulation (second contact)
INSERT INTO contacts (name, company, phone, email, notes, contact_type, trade)
VALUES (
    'Katie Stinnett',
    'Georgia Insulation',
    '+17705499561',
    'katie@georgiainsulation.com',
    'Works with Calvin Taylor. From VCF.',
    'vendor',
    'Insulation'
);
;
