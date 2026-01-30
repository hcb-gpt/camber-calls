ALTER TABLE public.financial_overrides
ADD CONSTRAINT financial_overrides_original_code_fkey 
FOREIGN KEY (original_cost_code) REFERENCES public.cost_code_taxonomy(code);

ALTER TABLE public.financial_overrides
ADD CONSTRAINT financial_overrides_override_code_fkey 
FOREIGN KEY (override_cost_code) REFERENCES public.cost_code_taxonomy(code);;
