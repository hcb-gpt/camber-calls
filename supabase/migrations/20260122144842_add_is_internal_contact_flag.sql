
-- Add is_internal flag for DATA-20's external contact filter
ALTER TABLE contacts 
ADD COLUMN IF NOT EXISTS is_internal BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN contacts.is_internal IS 'TRUE for TNF, HCB staff - should be filtered from external contact reports';

-- Flag known internal contacts
UPDATE contacts SET is_internal = TRUE
WHERE company IN ('TNF', 'Heartwood Custom Builders')
   OR name IN ('Zack Sittler', 'Chad Barlow', 'Randy Booth');
;
