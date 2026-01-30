-- Consolidate General Construction (4) + General Contractor (1) → General Contractor
UPDATE contacts 
SET trade = 'General Contractor'
WHERE trade = 'General Construction';;
