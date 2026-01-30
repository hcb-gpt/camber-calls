
-- Fix trade field misuse: 'Client' is not a trade, it's a contact_type
-- Clients don't have trades - they are homeowners
UPDATE contacts 
SET trade = NULL 
WHERE trade = 'Client';

-- Fix personal contacts with non-trade values
UPDATE contacts 
SET trade = NULL 
WHERE contact_type = 'personal' 
  AND trade IN ('Administration', 'Film/TV Production', 'Personal');
;
