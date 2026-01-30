
-- Update crew to bill through Top Notch Finishers, LLC
UPDATE contacts 
SET 
  company = 'Top Notch Finishers, LLC',
  trade = 'Carpentry',
  contact_type = 'vendor',
  updated_at = NOW()
WHERE phone IN ('+17702766981', '+17063192812', '+17062407305', '+14704692665');

-- Also update Zack's Heartwood record to add trade for when he's acting as Top Notch
-- (No, skip this - Zack stays internal/Heartwood. Top Notch is the company vendor.)
;
