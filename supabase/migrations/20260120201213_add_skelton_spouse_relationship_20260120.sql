
-- Add spouse relationship for Chris & Julie Skelton
INSERT INTO contact_relationships (contact_id, related_contact_id, relationship_type, relationship_label, strength, source)
VALUES 
  ('df138ef7-90e1-43ac-8101-2eab473740bc', '004eb461-c83b-4e00-95ec-75ceeef3bfcd', 'spouse', 'Husband', 100, 'manual'),
  ('004eb461-c83b-4e00-95ec-75ceeef3bfcd', 'df138ef7-90e1-43ac-8101-2eab473740bc', 'spouse', 'Wife', 100, 'manual');
;
