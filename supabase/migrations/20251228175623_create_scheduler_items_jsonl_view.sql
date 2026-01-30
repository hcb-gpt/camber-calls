
-- View: v_scheduler_items_jsonl
CREATE OR REPLACE VIEW v_scheduler_items_jsonl AS
SELECT 
  si.id,
  si.interaction_id,
  si.item_type,
  si.status,
  si.source,
  si.created_at,
  jsonb_build_object(
    'id', si.id,
    'interaction_id', si.interaction_id,
    'item_type', si.item_type,
    'title', si.title,
    'description', si.description,
    'time_hint', si.time_hint,
    'due_at_utc', to_char(si.due_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'start_at_utc', to_char(si.start_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'assignee', si.assignee,
    'status', si.status,
    'source', si.source,
    'created_at', to_char(si.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  ) as jsonl_line,
  jsonb_build_object(
    'id', si.id,
    'interaction_id', si.interaction_id,
    'item_type', si.item_type,
    'title', si.title,
    'description', si.description,
    'time_hint', si.time_hint,
    'due_at_utc', to_char(si.due_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'start_at_utc', to_char(si.start_at_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'assignee', si.assignee,
    'status', si.status,
    'source', si.source,
    'created_at', to_char(si.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  )::text as jsonl_text
FROM scheduler_items si;

COMMENT ON VIEW v_scheduler_items_jsonl IS 
  'JSONL output format for scheduler agent consumption. Use jsonl_text column for file export.';
;
