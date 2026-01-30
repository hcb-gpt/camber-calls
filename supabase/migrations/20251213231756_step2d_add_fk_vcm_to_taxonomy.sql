ALTER TABLE public.vendor_cost_code_map
ADD CONSTRAINT vendor_cost_code_map_code_fkey 
FOREIGN KEY (cost_code) REFERENCES public.cost_code_taxonomy(code);;
