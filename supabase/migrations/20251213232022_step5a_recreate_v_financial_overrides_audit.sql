DROP VIEW IF EXISTS public.v_financial_overrides_audit;

CREATE VIEW public.v_financial_overrides_audit AS
SELECT 
    fo.id AS override_id,
    i.interaction_id,
    i.channel,
    i.contact_name,
    i.event_at_local,
    TRIM(fo.original_cost_code) AS original_code,
    t_orig.name AS original_name,
    fo.original_confidence,
    TRIM(fo.override_cost_code) AS override_code,
    t_new.name AS override_name,
    fo.override_reason,
    fo.overridden_by,
    fo.created_at AS overridden_at
FROM financial_overrides fo
LEFT JOIN interactions i ON fo.interaction_id = i.id
LEFT JOIN cost_code_taxonomy t_orig ON fo.original_cost_code = t_orig.code
LEFT JOIN cost_code_taxonomy t_new ON fo.override_cost_code = t_new.code
ORDER BY fo.created_at DESC;;
