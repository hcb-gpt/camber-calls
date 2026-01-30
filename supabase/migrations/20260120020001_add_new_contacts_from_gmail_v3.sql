
-- Add new contacts discovered in Gmail (with contact_type)

-- Jose Araujo (Tony) - Painter
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Jose Araujo (Tony)',
  '+14045551234',
  'dominion9@icloud.com',
  'Dominion Painting',
  'Painting',
  'Painting Contractor',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Austin Atkinson - Air Georgia HVAC
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Austin Atkinson',
  '+18339024603',
  'austin@air-ga.net',
  'Air Georgia Heating & Cooling LLC',
  'HVAC',
  'Sales/Estimator',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;

-- Emily Boyer - Shane's wife, project contact
INSERT INTO contacts (id, name, phone, email, role, street, city, state, zip, contact_type)
VALUES (
  gen_random_uuid(),
  'Emily Boyer',
  '+17705840726',
  'emilysboyer@hotmail.com',
  'Homeowner',
  '410 E Central Ave',
  'Madison',
  'GA',
  '30650',
  'client'
) ON CONFLICT DO NOTHING;

-- Malcolm Hetzer - Hetzer Electric owner
INSERT INTO contacts (id, name, phone, email, company, trade, role, contact_type, floats_between_projects)
VALUES (
  gen_random_uuid(),
  'Malcolm Hetzer',
  '+17068184015',
  'malcolmhetzer4@gmail.com',
  'Hetzer Electric Company Ltd Co.',
  'Electrical',
  'Owner',
  'subcontractor',
  true
) ON CONFLICT DO NOTHING;
;
