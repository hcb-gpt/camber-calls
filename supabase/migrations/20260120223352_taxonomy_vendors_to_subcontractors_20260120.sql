-- Remaining vendors with physical trades should be subcontractors
-- These are people who do on-site work

UPDATE contacts
SET contact_type = 'subcontractor'
WHERE contact_type = 'vendor'
  AND trade IN (
    'Concrete', 'Electrical', 'Plumbing', 'HVAC', 'Roofing', 
    'Framing', 'Painting', 'Drywall', 'Insulation', 'Masonry',
    'Siding', 'Landscaping', 'Sitework', 'Tree Service', 'Septic',
    'Well Drilling', 'Land Clearing', 'Carpentry', 'Cleaning',
    'Waterproofing', 'Welding', 'Fencing', 'Exterior', 'Handyman',
    'General Construction', 'Restoration', 'Security', 'Locksmith',
    'Window Cleaning'
  );;
