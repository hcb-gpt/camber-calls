
-- Deep VCF Enrichment Batch 8: More construction trades

-- Tile contacts
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Rick (Tile)', '+17064747047', 'Tile', 'From VCF.', 'vendor'),
    ('Juan (Tile)', '+14044558911', 'Tile', 'From VCF.', 'vendor'),
    ('Jimmy Floyd', '+16787946020', 'Tile', 'From VCF.', 'vendor'),
    ('Michael (Tile)', '+16787179915', 'Tile', 'From VCF.', 'vendor'),
    ('Holt (Tile)', '+17068160771', 'Tile', 'From VCF.', 'vendor');

-- Glass/Mirror
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Clark Glass & Mirror', 'Clark Glass & Mirror', '+17065495145', 'Glass', 'From VCF.', 'vendor'),
    ('Austin (Atlanta Glass)', 'Atlanta Glass And Mirror', '+17705477768', 'Glass', 'From VCF.', 'vendor');

-- Painters
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Jay (Painter)', '+14044962077', 'Painting', 'From VCF.', 'vendor'),
    ('Sandro (Painter)', '+17062487168', 'Painting', 'From VCF.', 'vendor'),
    ('Enrique (Painter)', '+14048953691', 'Painting', 'From VCF.', 'vendor'),
    ('Frank (Painter)', '+14048072129', 'Painting', 'From VCF.', 'vendor'),
    ('Kyle Triplett', '+14782887923', 'Painting', 'From VCF.', 'vendor');

-- Plumber
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Brandon (Plumber)', '+17062555147', 'Plumbing', 'From VCF.', 'vendor');

-- Landscapers
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Ginger (Landscaper)', '+14042754339', 'Landscaping', 'From VCF.', 'vendor'),
    ('Leo Landscaping', '+17064744004', 'Landscaping', 'From VCF.', 'vendor');

-- Granite/Stone
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Sid Hailey', 'Starr Granite', '+17063190092', 'Countertops', 'From VCF.', 'vendor'),
    ('Mega Granite', 'Mega Granite', '+17702528313', 'Countertops', 'From VCF.', 'vendor');

-- Welding
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Tee Weldon', '+16788593775', 'Welding', 'From VCF.', 'vendor');

-- Drywall
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Rob Gratis', '+14047877174', 'Drywall', 'From VCF.', 'vendor'),
    ('Bonnie (Drywall)', '+17067130054', 'Drywall', 'From VCF.', 'vendor');

-- Electricians
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Dillon (Electrician)', '+17068167471', 'Electrical', 'From VCF.', 'vendor'),
    ('Corey (Electrician)', '+17068180671', 'Electrical', 'From VCF.', 'vendor');

-- Framers
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Salvador (Framer)', '+16786565463', 'Framing', 'From VCF.', 'vendor'),
    ('Sergio (Framer/Dove)', '+16789271339', 'Framing', 'Works with Brian Dove. From VCF.', 'vendor'),
    ('Johnny O''Kelly', '+17705604769', 'Framing', 'From VCF.', 'vendor');

-- HVAC
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Vance Cheatham', '+14046681658', 'HVAC', 'From VCF.', 'vendor'),
    ('Donald (Apalachee Air)', '+16789943735', 'HVAC', 'From VCF.', 'vendor'),
    ('Thomas HVAC', '+19122488300', 'HVAC', 'From VCF.', 'vendor'),
    ('Dylan Whitmire', '+17705484265', 'HVAC', 'Air Georgia. From VCF.', 'vendor');

-- Update Rodney Peppers HVAC
UPDATE contacts SET company = 'Peppers Heating & Air', trade = 'HVAC'
WHERE name = 'Rodney Peppers';

-- Roll-off/Hauling
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Landon Hill', '+17068182570', 'Hauling', 'Roll-off dumpsters. From VCF.', 'vendor');

-- Roofing
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Kirk (RWN Roofing)', '+17066141094', 'Roofing', 'From VCF.', 'vendor'),
    ('Paulk Roofing', '+17702679453', 'Roofing', 'From VCF.', 'vendor'),
    ('Tony Paulk', '+14045978622', 'Roofing', 'From VCF.', 'vendor'),
    ('Jacinto (Roofer)', '+17705277814', 'Roofing', 'From VCF.', 'vendor');

-- Doors
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Skylar (Select Door)', 'Select Door', '+17708463595', 'Doors', 'From VCF.', 'vendor');

-- Concrete
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Sergio (Concrete/Dove)', '+16784145608', 'Concrete', 'Works with Brian Dove. From VCF.', 'vendor'),
    ('Scott (Decorative Concrete)', '+17706542066', 'Concrete', 'Decorative concrete. From VCF.', 'vendor'),
    ('Fowler Concrete', '+17063422172', 'Concrete', 'Madison area. From VCF.', 'vendor');

-- Insulation
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Justin (Oconee Porter)', 'Oconee Porter Insulation', '+17062864363', 'Insulation', 'From VCF.', 'vendor');

-- Siding
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Baltozar (Siding)', '+14044066383', 'Siding', 'From VCF.', 'vendor'),
    ('German (Siding)', '+14045533359', 'Siding', 'From VCF.', 'vendor'),
    ('Miguel (Siding)', '+14044216673', 'Siding', 'From VCF.', 'vendor');

-- Flooring
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Clell (Flooring)', '+16783005463', 'Flooring', 'From VCF.', 'vendor'),
    ('Chili (Floor)', '+16788738703', 'Flooring', 'From VCF.', 'vendor'),
    ('M&T Flooring', '+14044252073', 'Flooring', 'From VCF.', 'vendor');

-- Mason
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Nelson (Mason)', '+16783498513', 'Masonry', 'From VCF.', 'vendor');

-- Tree Service
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Damon (Tree Farm)', 'Damon Tree Farm', '+17064742554', 'Tree Service', 'From VCF.', 'vendor'),
    ('Mike (Tree Guy)', NULL, '+17703186877', 'Tree Service', 'From VCF.', 'vendor'),
    ('FOY Tree Service Madison', 'FOY Insured Tree Service', '+17063428733', 'Tree Service', 'Madison area. From VCF.', 'vendor');

-- Gutters
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Rodrigo (Gutters)', '+16789434290', 'Gutters', 'From VCF.', 'vendor');

-- Trim
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Zachary (Trim Helper)', '+16783277257', 'Trim/Finish', 'Madison area. From VCF.', 'vendor');

-- Cleaning contacts
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Daphne (Cleaning)', '+17064738014', 'Cleaning', 'From VCF.', 'vendor'),
    ('Tonya (Cleaning)', '+15187753870', 'Cleaning', 'From VCF.', 'vendor'),
    ('Lucy (Cleaner)', '+17064745735', 'Cleaning', 'From VCF.', 'vendor'),
    ('Victoria (Cleaning)', '+17063722704', 'Cleaning', 'From VCF.', 'vendor');

-- Appliance
INSERT INTO contacts (name, company, phone, trade, notes, contact_type)
VALUES 
    ('Abby (Appliance)', 'Abby Appliance', '+16787273520', 'Appliances', 'From VCF.', 'vendor'),
    ('Abby (Dave''s Appliances)', 'Dave''s Appliances', '+17068709828', 'Appliances', 'From VCF.', 'vendor'),
    ('Askew Appliance', 'Askew Appliance', '+17064532234', 'Appliances', 'From VCF.', 'vendor');

-- Alarm
INSERT INTO contacts (name, phone, trade, notes, contact_type)
VALUES 
    ('Phillip (Alarm)', '+17062020781', 'Security/Alarm', 'From VCF.', 'vendor');
;
