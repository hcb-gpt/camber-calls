-- Fix remaining miscategorized contacts

-- Cabinetry builder (does on-site work) = subcontractor
UPDATE contacts SET contact_type = 'subcontractor' 
WHERE name = 'Travis Shadburn' AND trade = 'Cabinetry';

-- Auto body = other (not construction related)
-- Equine suppliers = supplier (sell horse stalls/equipment)
UPDATE contacts SET contact_type = 'supplier'
WHERE trade = 'Equine';

-- Developer = professional
UPDATE contacts SET contact_type = 'professional'
WHERE name = 'Brad Stephens' AND trade = 'Development';

-- Gerald Collins (carpenter looking for work) = subcontractor
UPDATE contacts SET contact_type = 'subcontractor'
WHERE name = 'Gerald Collins' AND trade = 'Carpentry';

-- Ryan Olivera (Square Design owner) = professional
UPDATE contacts SET contact_type = 'professional'
WHERE name = 'Ryan Olivera' AND trade = 'Design';

-- John Hill (financing) = professional
UPDATE contacts SET contact_type = 'professional'
WHERE name = 'John Hill' AND trade = 'Financing';

-- Insurance people without trade set = professional
UPDATE contacts SET contact_type = 'professional', trade = 'Insurance'
WHERE contact_type = 'other' 
  AND (company ILIKE '%insurance%' OR company ILIKE '%oakbridge%');

-- Attorneys = professional
UPDATE contacts SET contact_type = 'professional', trade = 'Legal'
WHERE contact_type = 'other' 
  AND (role ILIKE '%attorney%' OR company ILIKE '%law%' OR company ILIKE '%L.L.C.%');

-- Government clerk
UPDATE contacts SET contact_type = 'government', trade = 'Permits/Government'
WHERE name = 'Jody Higdon' AND company ILIKE '%clerk%';

-- Planning department
UPDATE contacts SET contact_type = 'government', trade = 'Permits/Government'
WHERE name = 'Tammy Osbourne' AND company ILIKE '%planning%';;
