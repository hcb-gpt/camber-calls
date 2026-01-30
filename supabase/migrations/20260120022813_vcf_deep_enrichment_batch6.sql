
-- Deep VCF Enrichment Batch 6: Equipment, rentals, and services

-- Equipment/Rentals
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Madison Rentals',
    'Madison Rentals',
    '+17063428665',
    'Equipment rental. From VCF.',
    'vendor'
);

INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Champion Lumber',
    'Champion Lumber',
    '+17064686518',
    'Lumber supplier. From VCF.',
    'vendor'
);

INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Social Circle Ace',
    'Social Circle Ace Home Center',
    '+17704643354',
    'Hardware store. From VCF.',
    'vendor'
);

INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Ag Pro',
    'Ag Pro',
    '+17063422332',
    'Equipment. From VCF.',
    'vendor'
);

-- Porta potty services
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

-- DH Pace / Overhead Door updates
UPDATE contacts SET 
    notes = COALESCE(notes, '') || ' | Darryl Thomas (Dept Coordinator): +14048723667, darryl.thomas@dhpace.com'
WHERE name = 'Paul Burchfield' AND company ILIKE '%overhead%';

-- Marybeth Hopkins - Heritage Equine Equipment
INSERT INTO contacts (name, company, phone, email, notes, contact_type)
VALUES (
    'Marybeth Hopkins',
    'Heritage Equine Equipment',
    '+17065755153',
    'marybeth@heritageequineequip.com',
    'Horse/equine equipment. From VCF.',
    'vendor'
);

-- Ginger Gray - Alex Smith Garden Design
INSERT INTO contacts (name, company, phone, email, notes, contact_type, trade)
VALUES (
    'Ginger Gray',
    'Alex Smith Garden Design Ltd',
    '+17704558878',
    'ginger@alexsmithgardendesign.com',
    'Landscape design. From VCF.',
    'vendor',
    'Landscaping'
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

-- Jeff Payne - Howard Payne
INSERT INTO contacts (name, company, phone, secondary_phone, email, notes, contact_type)
VALUES (
    'Jeffrey Payne',
    'Howard Payne',
    '+17704510136',
    '+16786484576',
    'jeffrey@howardpayne.com',
    'From VCF.',
    'vendor'
);

-- Garry Phelps - Phelps Welding
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Garry Phelps',
    'Phelps Welding & Radiator',
    '+17063423796',
    'phelpsweldingandradiator@gmail.com',
    'Owner',
    'Welding services. From VCF.',
    'vendor',
    'Welding'
);

-- Jay Bentley - Photography
INSERT INTO contacts (name, phone, secondary_phone, role, notes, contact_type)
VALUES (
    'Jay Bentley',
    '+14782341444',
    '+16782098787',
    'Photographer',
    'Jay Bentley Media. From VCF.',
    'other'
);

-- Charlie Byers - Real Estate Photography
INSERT INTO contacts (name, phone, role, notes, contact_type)
VALUES (
    'Charlie Byers',
    '+16789006204',
    'Real Estate Photographer',
    'From VCF.',
    'other'
);

-- Amanda - Atchimbault Interiors
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Amanda (Atchimbault)',
    'Atchimbault Interiors',
    '+17702311626',
    'Interior design. From VCF.',
    'vendor',
    'Interior Design'
);

-- Christine Kelley - Southern Elite HR
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Christine Kelley',
    'Southern Elite Contracting',
    '+14709487817',
    'HR',
    'From VCF.',
    'other'
);

-- Quetion Shelton - PEC
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Quetion Shelton',
    'PEC',
    '+14047337092',
    'From VCF.',
    'vendor'
);

-- Greg Tate
INSERT INTO contacts (name, phone, notes, contact_type)
VALUES (
    'Greg Tate',
    '+18137324504',
    'Candler Ln. From VCF.',
    'other'
);

-- Angie Sanders - Cleaning
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Angie Sanders',
    '+16787945746',
    'Cleaning',
    'Madison area. From VCF.',
    'vendor',
    'Cleaning'
);

-- Miguel Lopez - Family Pro Cleaning
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Miguel Lopez',
    'Family Pro Cleaning',
    '+17065082511',
    'From VCF.',
    'vendor',
    'Cleaning'
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
;
