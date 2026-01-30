
-- Deep VCF Enrichment Batch 5: Soil testing, utilities, specialty services

-- Soil testing contacts
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Shannon Hudgins',
    'Soil Profiles, Inc.',
    '+17708429895',
    'Soil Scientist',
    'Athens area septic soil testing. From VCF.',
    'vendor',
    'Soil Testing'
);

INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Taylor (GA Soil)',
    'Georgia Soil Mapping',
    '+17063101111',
    'Soil Testing',
    'Septic soil testing. From VCF.',
    'vendor',
    'Soil Testing'
);

INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Ross Scott',
    'Under Georgia Analysis',
    '+17064733618',
    'Soil Testing',
    'Septic soil testing. From VCF.',
    'vendor',
    'Soil Testing'
);

-- Georgia Power contacts
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Cody Patterson',
    'Georgia Power',
    '+14234634028',
    'copatter@southernco.com',
    'Engineer (Underground Service)',
    'From VCF.',
    'other'
);

INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Jody (GA Power)',
    'Georgia Power',
    '+17705500010',
    'Engineer (Underground Service)',
    'From VCF.',
    'other'
);

-- Central EMC
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Justin Vaughn',
    'Central EMC',
    '+17707757857',
    'Scheduling & System Operator',
    'From VCF.',
    'other'
);

-- DH Pace / Overhead Door
UPDATE contacts SET 
    secondary_phone = '+14048723667',
    email = 'paul.burchfield@dhpace.com',
    notes = COALESCE(notes, '') || ' | DH Pace company'
WHERE name = 'Paul Burchfield';

INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Darryl Thomas',
    'DH Pace',
    '+14048723667',
    'darryl.thomas@dhpace.com',
    'Department Coordinator',
    'Overhead doors. From VCF.',
    'vendor',
    'Doors'
);

-- Flooring contacts
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type, trade)
VALUES (
    'David Hillman',
    'Hillman Flooring',
    '+17703184843',
    '+17702710902',
    'david@hillmanflooring.com',
    'Vice President Sales',
    'From VCF.',
    'vendor',
    'Flooring'
);

INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Chris Aranda',
    'Innovative Flooring Group',
    '+14702342314',
    'Owner',
    'From VCF.',
    'vendor',
    'Flooring'
);

-- Tile contact (ref Boyer)
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'David Webb',
    '+17707805297',
    'Tile',
    'Referred by Boyer. From VCF.',
    'vendor',
    'Tile'
);

-- Stellar Windows and Doors
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Lucas Myhre',
    'Stellar Windows and Doors',
    '+14044238497',
    'lucas@stellarwd.com',
    'Sales',
    'From VCF.',
    'vendor',
    'Windows/Doors'
);

-- John Kopec - John Willis Homes
INSERT INTO contacts (name, company, phone, email, notes, contact_type)
VALUES (
    'John Kopec',
    'John Willis Homes',
    '+17706231496',
    'johnk@johnwilliscustomhomes.com',
    'Builder contact. From VCF.',
    'other'
);

-- Sherwin Williams
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Wilson (Sherwin Williams)',
    'Sherwin Williams Madison',
    '+17069010325',
    'Sales',
    'From VCF.',
    'vendor',
    'Paint'
);

-- Morgan Glass Services
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Chris (Morgan Glass)',
    'Morgan Glass Services',
    '+17704828701',
    'From VCF.',
    'vendor',
    'Glass'
);

-- Modern Concrete
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Justin McCrae',
    'Modern Concrete',
    '+14045832889',
    'From VCF.',
    'vendor',
    'Concrete'
);

-- Grayson - Oconee Concrete  
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Grayson (Oconee Concrete)',
    'Oconee Concrete',
    '+14784564602',
    'From VCF.',
    'vendor',
    'Concrete'
);

-- Marshal Davis - Home Repair
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Marshal Davis',
    'Davis Home Repair',
    '+17068180707',
    'From VCF.',
    'vendor'
);

-- Alex Davis - Stump Grinding
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Alex Davis',
    'Davis Stump Grinding',
    '+17062964493',
    'Athens area. From VCF.',
    'vendor',
    'Tree Service'
);

-- Sanchez - Painter
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Sanchez (Painter)',
    '+16787549796',
    'Painter',
    'From VCF.',
    'vendor',
    'Painting'
);

-- Johhny Hubbard - Painter Madison
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Johnny Hubbard',
    '+17707578325',
    'Painter',
    'Madison area. From VCF.',
    'vendor',
    'Painting'
);

-- Heritage Equine Equipment
INSERT INTO contacts (name, company, phone, email, notes, contact_type)
VALUES (
    'Marybeth Hopkins',
    'Heritage Equine Equipment',
    '+17065755153',
    'marybeth@heritageequineequip.com',
    'Equine/barn equipment. From VCF.',
    'vendor'
);

-- Precision Approach LLC
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Jacob Eisele',
    'Precision Approach, LLC',
    '+17064736483',
    'From VCF.',
    'vendor'
);
;
