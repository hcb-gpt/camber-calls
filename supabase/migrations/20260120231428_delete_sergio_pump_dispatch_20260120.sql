-- Delete pump dispatch number (incorrectly added as contact)
-- +14784562630 is a concrete pump company number, not Sergio's phone
-- Evidence: Sergio texted this number to Zack for scheduling

DELETE FROM contacts WHERE phone = '+14784562630' AND name ILIKE '%sergio%';;
