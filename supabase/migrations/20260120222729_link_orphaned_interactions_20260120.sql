-- Link orphaned interactions to their matching contacts
-- These are interactions where contact_phone matches a contact's phone or secondary_phone
-- but contact_id was never set

UPDATE interactions i
SET contact_id = c.id
FROM contacts c
WHERE (c.phone = i.contact_phone OR c.secondary_phone = i.contact_phone)
  AND i.contact_id IS NULL;;
