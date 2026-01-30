ALTER TABLE public.vendor_cost_code_map 
ADD COLUMN IF NOT EXISTS cost_code CHAR(4);;
