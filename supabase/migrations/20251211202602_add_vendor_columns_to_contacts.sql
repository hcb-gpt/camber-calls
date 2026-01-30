
-- Add vendor-specific columns to contacts table
ALTER TABLE public.contacts
ADD COLUMN IF NOT EXISTS trade text,
ADD COLUMN IF NOT EXISTS street text,
ADD COLUMN IF NOT EXISTS city text,
ADD COLUMN IF NOT EXISTS state text,
ADD COLUMN IF NOT EXISTS zip text,
ADD COLUMN IF NOT EXISTS core_business_keywords jsonb DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.contacts.trade IS 'Primary trade/specialty (e.g., Plumbing, Electrical, HVAC)';
COMMENT ON COLUMN public.contacts.core_business_keywords IS 'Keywords for matching interactions to vendors';
;
