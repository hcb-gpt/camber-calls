UPDATE public.financial_overrides fo
SET original_cost_code = cc.cost_code_number
FROM cost_codes cc
WHERE fo.original_cost_code_id = cc.id
  AND fo.original_cost_code IS NULL;

UPDATE public.financial_overrides fo
SET override_cost_code = cc.cost_code_number
FROM cost_codes cc
WHERE fo.override_cost_code_id = cc.id
  AND fo.override_cost_code IS NULL;;
