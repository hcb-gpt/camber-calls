-- Remove company email from Gatlin Hawkins (service@air-ga.net is company line)
UPDATE contacts 
SET email = NULL 
WHERE name = 'Gatlin Hawkins' AND email = 'service@air-ga.net';;
