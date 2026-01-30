create or replace view public.vw_cost_code_doc_export as
select
  id,
  cost_code_number,
  cost_code_name,
  division,
  phase_sequence,
  -- flatten JSONB array to comma-separated text for Wix consumption
  coalesce(
    (select string_agg(kw::text, ', ') 
     from jsonb_array_elements_text(cost_code_keywords) as kw),
    ''
  ) as keywords_flat,
  cost_code_keywords as keywords_json,
  created_at,
  updated_at
from public.cost_codes
order by phase_sequence, cost_code_number;;
