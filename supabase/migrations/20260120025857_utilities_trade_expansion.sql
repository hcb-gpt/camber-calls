
-- Add all utility coordination contacts to Utilities trade
UPDATE contacts SET trade = 'Utilities'
WHERE name IN (
    'Cody Patterson',      -- Georgia Power
    'Jody (GA Power)',     -- Georgia Power
    'Justin Vaughn',       -- Central EMC
    'Kee Kee Hunnicutt',   -- Madison Utility Billing
    'Curtis Walker'        -- Hancock County Water
)
AND contact_type = 'other';

-- Also update Adam Bates (Madison City Gas) if exists
UPDATE contacts SET trade = 'Utilities'
WHERE name = 'Adam Bates' AND company ILIKE '%gas%';
;
