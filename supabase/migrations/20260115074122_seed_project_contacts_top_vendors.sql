-- Seed project_contacts for top multi-project vendors to active projects
-- Source = 'data_inferred' so OPS knows to confirm/adjust
-- Active projects only (status = 'active')

WITH top_vendors AS (
  SELECT id, name, trade, contact_type
  FROM contacts
  WHERE id IN (
    'b0acfc66-7aef-4b6b-8754-d38cebc4df34',  -- Randy Booth (Masonry, 30 calls)
    '35ab3df2-543f-4cec-b24e-a1009254bd69',  -- Flynt Treadaway (Lumber, 23 calls)
    '2ddfe289-fb9a-4152-a5b7-b41685975069',  -- Brian Dove (Framing, 14 calls)
    'a0f3a2a5-ded8-4654-9066-55968bbc61c5',  -- Malcolm Hetzer (Electrical, 11 calls)
    '4b12395d-af47-4565-aa4c-1e49c0ce6add',  -- Zach Givens (Landscape, 7 calls)
    '98aa8a91-0351-4a71-9a6d-e04a55af73c6',  -- Taylor Shannon (Sitework, 7 calls)
    'a492a845-5dae-458c-bb59-9f11edb26e45',  -- Anthony Cottrell (Cabinetry, 4 calls)
    'f8901234-5678-90ab-fabc-456789012345',  -- Brandon Hightower (Survey, 3 calls)
    'e7f89012-3456-7890-efab-345678901234',  -- Eric Atkinson (Lumber, 3 calls)
    'ccad7cf8-fbed-41c6-9fb5-1d299fb5c7e2'   -- Gatlin Hawkins (HVAC, 2 calls)
  )
),
active_projects AS (
  SELECT id, name
  FROM projects
  WHERE status = 'active'
)
INSERT INTO project_contacts (id, contact_id, project_id, trade, is_active, source, created_at, updated_at)
SELECT 
  gen_random_uuid(),
  v.id,
  p.id,
  v.trade,
  true,
  'data_inferred',
  now(),
  now()
FROM top_vendors v
CROSS JOIN active_projects p
ON CONFLICT (contact_id, project_id) DO NOTHING;;
