
-- Add more new contacts discovered in Gmail

-- Zach Givens - Givens Landscaping
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Zach Givens',
  '+17705551234',
  'zgivens@bellsouth.net',
  'Givens Landscaping and Irrigation, Inc.',
  'Landscaping',
  'Owner',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Brian Dove - StructureMen
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Brian Dove',
  '+16784092410',
  'bkdove@me.com',
  'StructureMen, Inc.',
  'Framing/Concrete',
  'Owner',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Michael Strickland - Southeast Sitecast  
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Michael Strickland',
  '+17705551235',
  'sesitecast@yahoo.com',
  'Southeast Sitecast',
  'Concrete/Foundation',
  'Owner',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Hector Ordonez - Carter Lumber
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Hector Ordonez',
  '+17705551236',
  'hector.ordonez@carterlumber.com',
  'Carter Lumber',
  'Lumber/Materials',
  'Sales Rep',
  'vendor',
  true
) ON CONFLICT DO NOTHING;
;
