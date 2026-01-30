
-- Update existing contacts with emails from VCF

UPDATE contacts SET email = 'malcolmhetzer4@gmail.com'
WHERE name = 'Malcolm Hetzer' AND email IS NULL;

UPDATE contacts SET 
    company = 'Hetzer Electric',
    notes = COALESCE(notes, '') || ' | Works with Malcolm Hetzer'
WHERE name = 'Taylor Messer' AND company IS NULL;

UPDATE contacts SET email = 'zgivens@bellsouth.net'
WHERE name LIKE '%Zach%Givens%' AND email IS NULL;

UPDATE contacts SET email = 'calvin@georgiainsulation.com'
WHERE name = 'Calvin Taylor' AND email IS NULL;

UPDATE contacts SET 
    email = 'sesitecast@yahoo.com',
    role = 'Manager'
WHERE name = 'Michael Strickland' AND email IS NULL;

UPDATE contacts SET email = 'anthony@crossedchisels.com'
WHERE name = 'Anthony Cottrell' AND email IS NULL;

UPDATE contacts SET email = 'david@wwcompany.com'
WHERE name = 'David Woodbery' AND email IS NULL;

UPDATE contacts SET email = 'ljr_masonry@yahoo.com'
WHERE name = 'Luis Juarez' AND email IS NULL;

UPDATE contacts SET email = 'maynetileinc@gmail.com'
WHERE name = 'Bill Mayne' AND email IS NULL;

UPDATE contacts SET email = 'gb@gregbusch.com'
WHERE name = 'Greg Busch' AND email IS NULL;

-- Update Flynt Treadaway with email
UPDATE contacts SET email = 'flynt.treadaway@carterlumber.com'
WHERE name = 'Flynt Treadaway' AND email IS NULL;

-- Update Hector Ordonez with email
UPDATE contacts SET email = 'hector.ordonez@carterlumber.com'
WHERE name LIKE '%Hector%Ord%' AND email IS NULL;

-- Update Amy Champion with email
UPDATE contacts SET email = 'amy@windowconcepts.com'
WHERE name = 'Amy Champion' AND email IS NULL;

-- Update Daniel Martuscello with email
UPDATE contacts SET email = 'dmartuscello@rentile.com'
WHERE name = 'Daniel Martuscello' AND email IS NULL;

-- Update Randy Bryan with email
UPDATE contacts SET email = 'bryanshomerepair1@gmail.com'
WHERE name = 'Randy Bryan' AND email IS NULL;

-- Update Brandon Hightower with email
UPDATE contacts SET email = 'brandon@georgiacivil.com'
WHERE name = 'Brandon Hightower' AND email IS NULL;

-- Update Austin Atkinson with email
UPDATE contacts SET email = 'austin@air-ga.net'
WHERE name = 'Austin Atkinson' AND email IS NULL;
;
