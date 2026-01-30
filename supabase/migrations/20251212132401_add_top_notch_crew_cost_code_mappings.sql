
-- Add cost code mappings for Top Notch crew (Carpentry: 6020 primary, 6030 secondary)
INSERT INTO vendor_cost_code_map (contact_id, cost_code_id, mapping_type, confidence)
SELECT c.id, cc.id, 
  CASE WHEN cc.cost_code_number = '6020' THEN 'primary' ELSE 'secondary' END,
  1.00
FROM contacts c
CROSS JOIN cost_codes cc
WHERE c.company = 'Top Notch Finishers, LLC'
  AND cc.cost_code_number IN ('6020', '6030')
ON CONFLICT DO NOTHING;
;
