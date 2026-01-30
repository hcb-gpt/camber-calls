-- Malcolm Hetzer has contact_type='site_supervisor' which is non-standard
-- He's the owner of Hetzer Electric Company - should be 'vendor'
UPDATE contacts 
SET contact_type = 'vendor'
WHERE id = 'a0f3a2a5-ded8-4654-9066-55968bbc61c5' 
  AND contact_type = 'site_supervisor';;
