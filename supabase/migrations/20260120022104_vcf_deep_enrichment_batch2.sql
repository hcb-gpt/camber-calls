
-- Deep VCF Enrichment Batch 2: More vendors and county contacts

-- Cody Ariola - Fence Builder Madison
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Cody Ariola',
    '+13865902634',
    'Fence Builder',
    'Madison area. From VCF.',
    'vendor',
    'Fencing'
);

-- Doug Foy - Foy Tree Service
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Doug Foy',
    'Foy Tree Service',
    '+17063182538',
    'Owner',
    'Tree service. From VCF.',
    'vendor',
    'Tree Service'
);

-- Garrett - Classic City Trash
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Garrett (Classic City Trash)',
    'Classic City Trash Collection',
    '+17062067215',
    'From VCF.',
    'vendor'
);

-- Nick Arnold - Certified Dry (water/mold)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Nick Arnold',
    'Certified Dry Construction Cleaning',
    '+17062367160',
    'nick@certifieddry.com',
    'Owner',
    'Mud/Water/Mold remediation. From VCF.',
    'vendor',
    'Restoration'
);

-- Ryan Olivera - Square Design
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Ryan Olivera',
    'Square Design',
    '+17062471997',
    'ryan@squaredesign.com',
    'Owner',
    'From VCF.',
    'vendor',
    'Design'
);

-- JAMES Kimbler - Concrete Creations
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'James Kimbler',
    'Concrete Creations',
    '+17702948353',
    'From VCF.',
    'vendor',
    'Concrete'
);

-- Davis Maddox - Loader Work
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Davis Maddox',
    '+17064742931',
    'Loader/Equipment',
    'From VCF.',
    'vendor',
    'Sitework'
);

-- Frankie Slaughter - Slaughter Sales & Service
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Frankie Slaughter',
    'Slaughter Sales & Service Co.',
    '+17064740802',
    'Owner',
    'From VCF.',
    'vendor'
);

-- Ellis Johnson - Hundred Acre Farm
INSERT INTO contacts (name, company, phone, notes, contact_type)
VALUES (
    'Ellis Johnson',
    'Hundred Acre Farm',
    '+17068181851',
    'Farm manager. From VCF.',
    'other'
);

-- Chip McHugh - Newton Farm Manager
INSERT INTO contacts (name, phone, role, notes, contact_type)
VALUES (
    'Chip McHugh',
    '+17064740059',
    'Farm Manager',
    'Newton Farm. From VCF.',
    'other'
);

-- County/Government contacts
-- Brian Gardiner - Madison Building Code Inspector
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Brian Gardiner',
    'City of Madison, GA',
    '+14702495597',
    'Building Code Inspector',
    'From VCF.',
    'other'
);

-- Abby Willetts - Morgan County Plan Review
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Abby Willetts',
    'Morgan County Board of Commissioners',
    '+17063424373',
    'abby.willetts@morgancountyga.gov',
    'Plan Review',
    'From VCF.',
    'other'
);

-- Chuck Jarrell - Morgan County Director
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Chuck Jarrell',
    'Morgan County Board of Commissioners',
    '+17063424373',
    'chuck.jarrell@morgancountyga.gov',
    'Director',
    'From VCF.',
    'other'
);

-- Teresa Andrews - Hancock County Building & Planning
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type)
VALUES (
    'Teresa Andrews',
    'Hancock County, GA',
    '+17064440978',
    'tandrews@hancockcountyga.gov',
    'Director, Building & Planning',
    'From VCF.',
    'other'
);

-- Curtis Walker - Hancock County Water
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Curtis Walker',
    'Hancock County Water',
    '+17069980037',
    'Installer',
    'From VCF.',
    'other'
);

-- Tammy Osbourne - Madison Planning
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Tammy Osbourne',
    'Madison Planning and Development',
    '+17063421251',
    'Planning',
    'From VCF.',
    'other'
);

-- Brian Alliston - Morgan County Inspector
INSERT INTO contacts (name, company, phone, secondary_phone, email, role, notes, contact_type)
VALUES (
    'Brian Alliston',
    'Morgan County Planning and Development',
    '+17063436455',
    '+17063437748',
    'brian.alliston@morgancountyga.gov',
    'Building Inspector',
    'From VCF.',
    'other'
);
;
