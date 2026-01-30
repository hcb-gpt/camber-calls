
-- Shane Boyer: works at FRC Flooring, has trade=Flooring, role says Homeowner (confusing)
-- He's clearly a vendor/subcontractor for flooring
UPDATE contacts 
SET contact_type = 'vendor', role = 'Sales Rep'
WHERE phone = '+17705840725' AND name = 'Shane Boyer';

-- Brad Stephens: Developer is a valid trade for a land developer/homebuilder
-- contact_type=vendor is correct, trade=Development is fine
-- No change needed
;
