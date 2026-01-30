-- TYPE ALIGNMENT PLAN P2: Vendor Deprecation
-- Per STRATA-25 Type Alignment Plan v0.1

-- Step 1: Backup vendor contacts
CREATE TABLE contacts_vendor_backup AS 
SELECT id, name, trade, contact_type 
FROM contacts 
WHERE contact_type = 'vendor';

-- Step 2: All current vendors have service trades (tile, garage doors, electrical)
-- These are subcontractors, not suppliers
UPDATE contacts SET contact_type = 'subcontractor'
WHERE contact_type = 'vendor';

COMMENT ON TABLE contacts_vendor_backup IS 
'Backup of contacts with contact_type=vendor before P2 deprecation. Created 2026-01-26.';;
