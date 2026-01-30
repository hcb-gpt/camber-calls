DROP VIEW IF EXISTS public.v_vendor_inference_summary;

CREATE VIEW public.v_vendor_inference_summary AS
SELECT 
    c.name AS vendor_name,
    c.trade,
    count(DISTINCT vcc.cost_code) AS mapped_cost_codes,
    string_agg(DISTINCT TRIM(vcc.cost_code), ', ' ORDER BY TRIM(vcc.cost_code)) AS cost_codes,
    CASE
        WHEN c.id IN (
            SELECT (jsonb_array_elements_text(config_value))::uuid 
            FROM inference_config 
            WHERE config_key = 'p0_vendor_ids'
        ) THEN 'P0'
        ELSE 'P1'
    END AS priority_tier
FROM contacts c
LEFT JOIN vendor_cost_code_map vcc ON c.id = vcc.contact_id
WHERE c.contact_type = 'vendor'
GROUP BY c.id, c.name, c.trade
ORDER BY c.trade, c.name;;
