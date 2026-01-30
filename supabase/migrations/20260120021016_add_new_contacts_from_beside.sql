
-- Add new vendor contacts discovered from Beside data

-- Amy Brickman - Traditions In Tile (active Beside user)
INSERT INTO contacts (name, company, phone, email, role, notes, contact_type, trade)
VALUES (
    'Amy Brickman',
    'Traditions In Tile & Stone',
    '+17062014173',
    'amy.brickman@traditionsintile.com',
    'Showroom Designer & Sales',
    'Office: 706.543.0500 x10609, Fax: 706.543.0510. Beside user. Moss project selections.',
    'vendor',
    'Tile'
);

-- Dana - Roseman Plumbing (active Beside user)
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Dana (Roseman)',
    'Roseman Plumbing LLC',
    '+17062246511',
    NULL,
    'Office: 706-247-2074. Beside user.',
    'vendor',
    'Plumbing'
);

-- Bobby - Accent Granite (active Beside user)
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Bobby (Accent Granite)',
    'Accent Granite Interiors LLC',
    '+17069880485',
    'Works with Dwayne Brown. Beside user.',
    'vendor',
    'Granite/Stone'
);

-- Austin - Georgia Kitchens (active Beside user)
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Austin (Georgia Kitchens)',
    'Georgia Kitchens',
    '+14703509797',
    'Second contact at GK (Joe Laboon is primary). Beside user.',
    'vendor',
    'Appliances'
);

-- Steve Hayes - Hayes Tile (active Beside user)
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Steve Hayes',
    'Hayes Tile',
    '+17066144454',
    'Tile Contractor',
    'Beside user.',
    'vendor',
    'Tile'
);

-- Kip Carter - Sheetrock
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Kip Carter',
    NULL,
    '+14045979084',
    'Sheetrock/Drywall',
    'Sheetrock/drywall work. From Beside.',
    'vendor',
    'Drywall'
);

-- Ian McClure - Landscaper (active Beside user)
INSERT INTO contacts (name, phone, role, notes, contact_type, trade)
VALUES (
    'Ian McClure',
    '+17062150789',
    'Landscaper',
    'Beside user.',
    'vendor',
    'Landscaping'
);

-- John David - Window Concepts
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'John David',
    'Window Concepts Ltd.',
    '+17065901850',
    'Second contact (Amy Champion is primary). From Beside.',
    'vendor',
    'Windows/Doors'
);

-- Tech - Air Georgia (additional support line)
INSERT INTO contacts (name, company, phone, role, notes, contact_type, trade)
VALUES (
    'Tech (Air GA)',
    'Air Georgia Heating & Cooling LLC',
    '+17703241263',
    'Technical Support',
    'Technical support line. From Beside.',
    'vendor',
    'HVAC'
);

-- Drew - Oconee County Inspector (useful for permits)
INSERT INTO contacts (name, company, phone, role, notes, contact_type)
VALUES (
    'Drew (Inspector)',
    'Oconee County',
    '+17622329330',
    'Inspector',
    'Oconee County Inspector. From Beside. Useful for permits.',
    'other'
);

-- Mark - Vintage Stone
INSERT INTO contacts (name, company, phone, notes, contact_type, trade)
VALUES (
    'Mark (Vintage Stone)',
    'Vintage Stone',
    '+17065672896',
    'Stone vendor. Beside user.',
    'vendor',
    'Stone/Masonry'
);
;
