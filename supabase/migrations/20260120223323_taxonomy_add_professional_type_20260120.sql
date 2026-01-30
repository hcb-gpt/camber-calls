-- Reclassify professional services
-- Licensed professionals providing design/consulting, not physical labor

UPDATE contacts
SET contact_type = 'professional'
WHERE contact_type IN ('vendor', 'subcontractor')
  AND trade IN (
    'Architecture', 'Engineering', 'Survey', 'Soil Scientist', 
    'Testing/Inspection', 'Insurance', 'Banking', 'Legal', 
    'Bookkeeping', 'Interior Design', 'Photography'
  );;
