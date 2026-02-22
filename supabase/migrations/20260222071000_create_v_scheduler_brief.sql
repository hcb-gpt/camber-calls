CREATE OR REPLACE VIEW public.v_scheduler_brief AS
WITH scoped AS (
  SELECT
    si.project_id,
    COALESCE(p.name, 'Unassigned') AS project_name,
    si.id,
    si.title,
    si.assignee,
    si.item_type,
    si.status,
    si.due_at_utc,
    CASE
      WHEN si.due_at_utc < now() THEN 'overdue'
      WHEN si.due_at_utc <= now() + interval '7 days' THEN 'due_next_7d'
      ELSE 'outside_window'
    END AS due_bucket
  FROM public.scheduler_items si
  LEFT JOIN public.projects p ON p.id = si.project_id
  WHERE si.status = 'pending'
    AND si.due_at_utc IS NOT NULL
    AND si.due_at_utc <= now() + interval '7 days'
),
agg AS (
  SELECT
    project_id,
    project_name,
    due_bucket,
    count(*)::bigint AS item_count,
    min(due_at_utc) AS earliest_due_at_utc,
    max(due_at_utc) AS latest_due_at_utc
  FROM scoped
  GROUP BY project_id, project_name, due_bucket
)
SELECT
  project_id,
  project_name,
  due_bucket,
  item_count,
  earliest_due_at_utc,
  latest_due_at_utc
FROM agg;
