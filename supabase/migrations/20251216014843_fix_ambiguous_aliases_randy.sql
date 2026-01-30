-- Remove ambiguous "Randy" and "Randy B" aliases that match multiple people
-- Keep only distinguishing aliases

-- Randy Booth (internal) - keep role-specific aliases
UPDATE contacts 
SET aliases = ARRAY['Randy Booth', 'R Booth', 'R. Booth', 'Booth']
WHERE name = 'Randy Booth';

-- Randy Bryan (vendor/plumber) - keep company-specific aliases  
UPDATE contacts 
SET aliases = ARRAY['Randy Bryan', 'R Bryan', 'Bryans Plumbing', 'Bryan Plumbing', 'Bryans Home Repair', 'Bryan']
WHERE name = 'Randy Bryan';
;
