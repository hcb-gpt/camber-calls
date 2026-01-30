UPDATE public.vendor_cost_code_map vcm
SET cost_code = cc.cost_code_number
FROM cost_codes cc
WHERE vcm.cost_code_id = cc.id
  AND vcm.cost_code IS NULL;;
