ALTER TABLE public.financial_overrides 
ADD COLUMN IF NOT EXISTS original_cost_code CHAR(4);

ALTER TABLE public.financial_overrides 
ADD COLUMN IF NOT EXISTS override_cost_code CHAR(4);;
