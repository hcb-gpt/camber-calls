
-- Backfill tasks from calls_raw.raw_snapshot_json.tasks into scheduler_items
-- Hash formula: md5(interaction_uuid||'|'||item_type||'|'||coalesce(title,''))

INSERT INTO scheduler_items (
    interaction_id,
    item_type,
    title,
    description,
    assignee,
    due_at_utc,
    status,
    source,
    item_hash,
    meta
)
SELECT 
    i.id as interaction_id,
    'task' as item_type,
    task_obj->>'task' as title,
    NULL as description,
    task_obj->>'owner' as assignee,
    CASE 
        WHEN task_obj->>'due_date' ~ '^\d{4}-\d{2}-\d{2}' 
        THEN (task_obj->>'due_date')::timestamptz 
        ELSE NULL 
    END as due_at_utc,
    'pending' as status,
    'ai' as source,
    md5(i.id::text || '|' || 'task' || '|' || COALESCE(task_obj->>'task', '')) as item_hash,
    jsonb_build_object(
        'priority', task_obj->>'priority',
        'source_interaction_id', c.interaction_id,
        'backfill_batch', 'call_tasks_20251228'
    ) as meta
FROM calls_raw c
JOIN interactions i ON c.interaction_id = i.interaction_id
CROSS JOIN LATERAL jsonb_array_elements(c.raw_snapshot_json->'tasks') as task_obj
WHERE jsonb_array_length(COALESCE(c.raw_snapshot_json->'tasks', '[]'::jsonb)) > 0
  AND task_obj->>'task' IS NOT NULL
  AND task_obj->>'task' != ''
ON CONFLICT (interaction_id, item_hash) DO NOTHING
;
