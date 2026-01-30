-- Add generated column for digits-only phone matching (optional, for performance)
ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS phone_digits text 
GENERATED ALWAYS AS (regexp_replace(phone, '[^0-9]', '', 'g')) STORED;

-- Index on phone_digits for fast lookups
CREATE INDEX IF NOT EXISTS idx_contacts_phone_digits 
ON public.contacts (phone_digits);

-- Add generated column for secondary_phone digits
ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS secondary_phone_digits text 
GENERATED ALWAYS AS (regexp_replace(COALESCE(secondary_phone, ''), '[^0-9]', '', 'g')) STORED;

CREATE INDEX IF NOT EXISTS idx_contacts_secondary_phone_digits 
ON public.contacts (secondary_phone_digits) 
WHERE secondary_phone_digits != '';

-- Create RPC function for contact lookup
CREATE OR REPLACE FUNCTION public.lookup_contact_by_phone(p_phone text)
RETURNS TABLE (
    contact_id uuid,
    contact_name text,
    contact_company text,
    contact_type text,
    matched_on text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_digits text;
BEGIN
    -- Normalize input to digits only
    v_digits := regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g');
    
    -- Return empty if no digits
    IF v_digits = '' OR length(v_digits) < 7 THEN
        RETURN;
    END IF;
    
    -- Try exact match on phone_digits first
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.company,
        c.contact_type,
        'phone'::text
    FROM contacts c
    WHERE c.phone_digits = v_digits
    LIMIT 1;
    
    IF FOUND THEN RETURN; END IF;
    
    -- Try secondary_phone_digits
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.company,
        c.contact_type,
        'secondary_phone'::text
    FROM contacts c
    WHERE c.secondary_phone_digits = v_digits
      AND c.secondary_phone_digits != ''
    LIMIT 1;
    
    IF FOUND THEN RETURN; END IF;
    
    -- Try suffix match (last 10 digits) for flexibility
    IF length(v_digits) >= 10 THEN
        RETURN QUERY
        SELECT 
            c.id,
            c.name,
            c.company,
            c.contact_type,
            'phone_suffix'::text
        FROM contacts c
        WHERE RIGHT(c.phone_digits, 10) = RIGHT(v_digits, 10)
        LIMIT 1;
    END IF;
END;
$$;

-- Grant execute to service_role (Pipedream uses service key)
GRANT EXECUTE ON FUNCTION public.lookup_contact_by_phone(text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.lookup_contact_by_phone(text) FROM anon, authenticated;

COMMENT ON FUNCTION public.lookup_contact_by_phone IS 
'Lookup contact by phone number. Normalizes input to digits and matches against phone/secondary_phone. Returns first match.';;
