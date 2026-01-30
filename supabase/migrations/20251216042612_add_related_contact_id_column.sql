-- Add related_contact_id for family/business relationships
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS related_contact_id UUID REFERENCES contacts(id);
COMMENT ON COLUMN contacts.related_contact_id IS 'FK to related contact (spouse, family member, business partner). Use notes for relationship type.';;
