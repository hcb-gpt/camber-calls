
-- Add more new contacts discovered in Gmail

-- Anna Self - Georgia Insulation
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Anna Self',
  '+17705551237',
  'anna@georgiainsulation.com',
  'Georgia Insulation',
  'Insulation',
  'Office/Admin',
  'vendor',
  true
) ON CONFLICT DO NOTHING;

-- Calvin Taylor - Georgia Insulation  
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Calvin Taylor',
  '+17705551238',
  'calvin@georgiainsulation.com',
  'Georgia Insulation',
  'Insulation',
  'Owner/Estimator',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Tawney Patterson - PDI (plumbing supplier)
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Tawney Patterson',
  '+17705551239',
  'tpatterson@relyonpdi.com',
  'PDI (Plumbing Distributors Inc)',
  'Plumbing Supplies',
  'Showroom Sales',
  'vendor',
  true
) ON CONFLICT DO NOTHING;

-- Update Alicia Cottrell with confirmed phone
UPDATE contacts SET 
  phone = '+17063869977'
WHERE name = 'Alicia Cottrell' AND phone IS NULL;
;
