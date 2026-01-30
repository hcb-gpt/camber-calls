-- Malcolm Hetzer is a subcontractor (electrical), not vendor
UPDATE contacts 
SET contact_type = 'subcontractor'
WHERE name = 'Malcolm Hetzer' AND trade = 'Electrical';;
