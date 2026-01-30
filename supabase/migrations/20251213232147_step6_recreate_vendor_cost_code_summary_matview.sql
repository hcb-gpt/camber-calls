DROP MATERIALIZED VIEW IF EXISTS public.vendor_cost_code_summary;

CREATE MATERIALIZED VIEW public.vendor_cost_code_summary AS
SELECT 
    c.id AS contact_id,
    c.name AS vendor_name,
    c.company,
    c.trade,
    TRIM(t.code) AS cost_code_number,
    t.name AS cost_code_name,
    t.division,
    t.phase_seq AS phase_sequence,
    vcm.mapping_type,
    vcm.confidence
FROM contacts c
JOIN vendor_cost_code_map vcm ON c.id = vcm.contact_id
JOIN cost_code_taxonomy t ON vcm.cost_code = t.code
ORDER BY c.trade, vcm.mapping_type, t.phase_seq;

CREATE INDEX IF NOT EXISTS idx_vendor_cost_code_summary_contact 
ON vendor_cost_code_summary(contact_id);;
