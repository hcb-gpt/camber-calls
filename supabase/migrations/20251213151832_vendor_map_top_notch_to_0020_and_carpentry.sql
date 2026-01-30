
-- Migration: Update Top Notch Finishers vendor mappings per Strat memo v2
-- Primary: 0020 (Jobsite Support) - high weight
-- Secondary: carpentry codes (6020, 6030, 6040) - moderate weight

-- Get the new 0020 cost code ID
WITH cost_code_0020 AS (
  SELECT id FROM cost_codes WHERE cost_code_number = '0020'
),
top_notch_contacts AS (
  SELECT id FROM contacts WHERE company = 'Top Notch Finishers, LLC'
),
carpentry_codes AS (
  SELECT id, cost_code_number 
  FROM cost_codes 
  WHERE cost_code_number IN ('6020', '6030', '6040')
)

-- First, update existing 6020 mappings from 'primary' to 'secondary'
-- to reflect that jobsite support (0020) is now their primary work
UPDATE vendor_cost_code_map
SET 
  mapping_type = 'secondary',
  confidence = 0.85,
  updated_at = now()
WHERE contact_id IN (SELECT id FROM top_notch_contacts)
  AND cost_code_id = (SELECT id FROM cost_codes WHERE cost_code_number = '6020')
  AND mapping_type = 'primary';

-- Add 0020 as primary mapping for all Top Notch contacts
INSERT INTO vendor_cost_code_map (contact_id, cost_code_id, mapping_type, confidence)
SELECT 
  c.id,
  cc.id,
  'primary',
  1.00
FROM contacts c
CROSS JOIN cost_codes cc
WHERE c.company = 'Top Notch Finishers, LLC'
  AND cc.cost_code_number = '0020'
ON CONFLICT DO NOTHING;

-- Add 6040 (Cabinetry) as secondary mapping for carpentry work contexts
INSERT INTO vendor_cost_code_map (contact_id, cost_code_id, mapping_type, confidence)
SELECT 
  c.id,
  cc.id,
  'secondary',
  0.75
FROM contacts c
CROSS JOIN cost_codes cc
WHERE c.company = 'Top Notch Finishers, LLC'
  AND cc.cost_code_number = '6040'
ON CONFLICT DO NOTHING;
;
