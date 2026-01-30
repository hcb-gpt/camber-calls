-- Reclassify government/utility contacts
UPDATE contacts
SET contact_type = 'government'
WHERE contact_type IN ('vendor', 'subcontractor', 'other')
  AND (
    trade IN ('Permits/Government', 'Utilities')
    OR company ILIKE '%county%'
    OR company ILIKE '%city of%'
    OR company ILIKE '%georgia power%'
    OR company ILIKE '%emc%'
  );;
