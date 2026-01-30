-- Drop orphaned UUID columns that referenced the now-deleted cost_codes table

-- 1. Drop cost_code_id from vendor_cost_code_map (old FK to cost_codes.id)
ALTER TABLE public.vendor_cost_code_map DROP COLUMN IF EXISTS cost_code_id;

-- 2. Drop original_cost_code_id from financial_overrides (old FK to cost_codes.id)
ALTER TABLE public.financial_overrides DROP COLUMN IF EXISTS original_cost_code_id;

-- 3. Drop override_cost_code_id from financial_overrides (old FK to cost_codes.id)
ALTER TABLE public.financial_overrides DROP COLUMN IF EXISTS override_cost_code_id;

-- 4. Make new cost_code column NOT NULL in vendor_cost_code_map
ALTER TABLE public.vendor_cost_code_map ALTER COLUMN cost_code SET NOT NULL;;
