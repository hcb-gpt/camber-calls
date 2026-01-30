
-- Add addresses for existing client contacts from VCF data

-- Ginny Mellinger
UPDATE contacts SET 
    street = '2033 Spartan Ests Dr',
    city = 'Athens',
    state = 'GA',
    zip = '30606'
WHERE name = 'Ginny Mellinger';

-- Brian Young
UPDATE contacts SET 
    street = '1101 Red Oak Ct',
    city = 'Watkinsville',
    state = 'GA',
    zip = '30677'
WHERE name = 'Brian Young';

-- Norma Young (shares address with Brian)
UPDATE contacts SET 
    street = '1101 Red Oak Ct',
    city = 'Watkinsville',
    state = 'GA',
    zip = '30677'
WHERE name = 'Norma Young';

-- Lou Winship
UPDATE contacts SET 
    street = '4541 Bethany Rd',
    city = 'Buckhead',
    state = 'GA',
    zip = '30625'
WHERE name = 'Lou Winship';

-- Blanton Winship
UPDATE contacts SET 
    street = '4541 Bethany Rd',
    city = 'Buckhead',
    state = 'GA',
    zip = '30625'
WHERE name = 'Blanton Winship';

-- Kaylen Hurley
UPDATE contacts SET 
    street = '2401 Downs Creek Dr',
    city = 'Athens',
    state = 'GA',
    zip = '30606'
WHERE name = 'Kaylen Hurley';

-- Bo Hurley (Joseph Hurley)
UPDATE contacts SET 
    street = '2401 Downs Creek Dr',
    city = 'Athens',
    state = 'GA',
    zip = '30606'
WHERE name = 'Bo Hurley';

-- Mike Kreikemeier
UPDATE contacts SET 
    street = '651 N Main St',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name = 'Mike Kreikemeier';

-- Bromley Kreikemeier
UPDATE contacts SET 
    street = '651 N Main St',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name = 'Bromley Kreikemeier';

-- Steven Permar
UPDATE contacts SET 
    street = '1001 Hickory Grove Church Rd',
    city = 'Sparta',
    state = 'GA',
    zip = '31087'
WHERE name = 'Steven Permar';

-- Debbie Permar
UPDATE contacts SET 
    street = '1001 Hickory Grove Church Rd',
    city = 'Sparta',
    state = 'GA',
    zip = '31087'
WHERE name = 'Debbie Permar';

-- Shayelyn Woodbery
UPDATE contacts SET 
    street = '2190 Enterprise Rd',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name = 'Shayelyn Woodbery';

-- Emily Boyer
UPDATE contacts SET 
    street = '410 Central Ave',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name = 'Emily Boyer';

-- Shane Boyer
UPDATE contacts SET 
    street = '410 Central Ave',
    city = 'Madison',
    state = 'GA',
    zip = '30650'
WHERE name = 'Shane Boyer';
;
