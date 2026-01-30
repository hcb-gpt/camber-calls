-- Reclassify material/product suppliers
-- These are companies you BUY FROM, not companies that do on-site work

UPDATE contacts
SET contact_type = 'supplier'
WHERE contact_type IN ('vendor', 'subcontractor')
  AND trade IN (
    'Lumber', 'Appliances', 'Plumbing Fixtures', 'Windows', 'Doors', 
    'Countertops', 'Tile', 'Flooring', 'Lighting', 'Fireplaces',
    'Building Materials', 'Local Supply', 'Equipment', 'Temporary Facilities',
    'Glass', 'Garage Doors', 'Gutters', 'Millwork'
  );;
