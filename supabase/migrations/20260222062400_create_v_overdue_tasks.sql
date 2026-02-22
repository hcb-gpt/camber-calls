CREATE OR REPLACE VIEW public.v_overdue_tasks AS
SELECT
  si.project_id,
  p.name AS project_name,
  si.title,
  si.assignee,
  si.due_at_utc,
  EXTRACT(DAY FROM now() - si.due_at_utc) AS days_overdue,
  si.item_type,
  si.financial_json IS NOT NULL AS has_financial_json
FROM public.scheduler_items si
LEFT JOIN public.projects p ON p.id = si.project_id
WHERE si.status = 'pending'
  AND si.due_at_utc < now()
ORDER BY si.due_at_utc ASC;
