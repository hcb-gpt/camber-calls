-- TYPE ALIGNMENT PLAN P1: Role Normalization
-- Per STRATA-25 Type Alignment Plan v0.1
-- Step 1: Backup current state

CREATE TABLE contacts_role_backup AS 
SELECT id, role, trade, contact_type, updated_at 
FROM contacts;

COMMENT ON TABLE contacts_role_backup IS 
'Backup of contacts.role before Type Alignment P1 normalization. Created 2026-01-26.';;
