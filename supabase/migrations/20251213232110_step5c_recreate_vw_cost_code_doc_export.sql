DROP VIEW IF EXISTS public.vw_cost_code_doc_export;

CREATE VIEW public.vw_cost_code_doc_export AS
SELECT 
    TRIM(code) AS id,
    TRIM(code) AS cost_code_number,
    name AS cost_code_name,
    division,
    phase_seq AS phase_sequence,
    COALESCE(keywords, '') AS keywords_flat,
    keywords AS keywords_json,
    created_at,
    updated_at
FROM cost_code_taxonomy
WHERE row_type = 'COST_CODE'
ORDER BY phase_seq, code;;
