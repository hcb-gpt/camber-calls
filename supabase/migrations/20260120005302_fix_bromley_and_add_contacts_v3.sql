
-- 1. Fix Bromley duplicate: 
-- a) Update phone on older record
UPDATE contacts 
SET phone = '+17703312520'
WHERE id = 'b8a1c2d3-e4f5-6789-abcd-ef0123456789';

-- b) Move interactions from duplicate to original
UPDATE interactions 
SET contact_id = 'b8a1c2d3-e4f5-6789-abcd-ef0123456789'
WHERE contact_id = '1ffc7c91-e12c-450d-9c03-16710ef31fdf';

-- c) Delete duplicate
DELETE FROM contacts 
WHERE id = '1ffc7c91-e12c-450d-9c03-16710ef31fdf';

-- 2. Add high-value contacts from Beside

-- Mike Becker - client with closed project
INSERT INTO contacts (id, phone, name, contact_type, role, notes)
VALUES (gen_random_uuid(), '+16784772532', 'Mike Becker', 'client', 'Homeowner', 'Closed project');

-- Lauren Anthony - Anything Fireplace
INSERT INTO contacts (id, phone, name, contact_type, company, trade, email)
VALUES (gen_random_uuid(), '+16788338072', 'Lauren Anthony', 'vendor', 'Anything Fireplace', 'Fireplaces', 'info@anythingfireplace.com');

-- Cindy Maldonado - Eden's wife
INSERT INTO contacts (id, phone, name, contact_type, notes)
VALUES (gen_random_uuid(), '+14043545504', 'Cindy Maldonado', 'personal', 'Eden Quevedo''s wife');

-- Rob Gas Guy
INSERT INTO contacts (id, phone, name, contact_type, trade, notes)
VALUES (gen_random_uuid(), '+17068190985', 'Rob (Gas Guy)', 'vendor', 'Gas/Plumbing', 'Beside contact name: Rob Gas Guy');

-- Sergio Dove Concrete
INSERT INTO contacts (id, phone, name, contact_type, trade)
VALUES (gen_random_uuid(), '+16784145608', 'Sergio (Dove Concrete)', 'vendor', 'Concrete');

-- Joe KCI Sheetrock
INSERT INTO contacts (id, phone, name, contact_type, company, trade)
VALUES (gen_random_uuid(), '+17708276063', 'Joe (KCI Sheetrock)', 'vendor', 'KCI', 'Drywall');

-- Paul Burchfield - Overhead Door Company
INSERT INTO contacts (id, phone, name, contact_type, company, trade, email)
VALUES (gen_random_uuid(), '+17063803087', 'Paul Burchfield', 'vendor', 'Overhead Door Company / DH Pace', 'Garage Doors', 'Paul.Burchfield@dhpace.com');

-- Justin - Central EMC
INSERT INTO contacts (id, phone, name, contact_type, company, role, trade)
VALUES (gen_random_uuid(), '+14707652123', 'Justin (Central EMC)', 'vendor', 'Central EMC', 'Field Engineer', 'Power/Electric');

-- Damon Tree Farm
INSERT INTO contacts (id, phone, name, contact_type, trade)
VALUES (gen_random_uuid(), '+17064742554', 'Damon (Tree Farm)', 'vendor', 'Trees/Lumber');

-- Marybeth Hopkins - Heritage Equine Equipment
INSERT INTO contacts (id, phone, name, contact_type, company, email)
VALUES (gen_random_uuid(), '+17065755153', 'Marybeth Hopkins', 'vendor', 'Heritage Equine Equipment', 'marybeth@heritageequineequip.com');

-- Lauren Poynter White - Fieldstone Center
INSERT INTO contacts (id, phone, name, contact_type, company, role, email)
VALUES (gen_random_uuid(), '+14047870086', 'Lauren Poynter White', 'vendor', 'Fieldstone Center', 'President', 'LaurenP@fieldstonecenter.com');
;
