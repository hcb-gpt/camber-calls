
-- Read-only compatibility view: call_tasks as scheduler_items format
CREATE OR REPLACE VIEW v_call_tasks_as_scheduler_items AS
SELECT 
    gen_random_uuid() as id,
    i.id as interaction_id,
    'task'::text as item_type,
    ct.task_text as title,
    NULL::text as description,
    NULL::text as time_hint,
    NULL::timestamptz as start_at_utc,
    CASE WHEN ct.due_date IS NOT NULL 
         THEN ct.due_date::timestamp AT TIME ZONE 'America/New_York' AT TIME ZONE 'UTC'
         ELSE NULL 
    END as due_at_utc,
    ct.owner as assignee,
    'pending'::text as status,
    NULL::jsonb as financial_json,
    2 as scheduler_schema_version,
    ct.created_at_utc as created_at,
    ct.updated_at_utc as updated_at,
    NULL::jsonb as payload,
    jsonb_build_object('source_table', 'call_tasks', 'priority', ct.priority) as meta,
    ct.source,
    MD5(i.id::text || 'task' || ct.task_text) as item_hash,
    -- Extra columns for delta analysis
    ct.id as original_call_task_id,
    ct.interaction_id as original_text_interaction_id
FROM call_tasks ct
JOIN interactions i ON i.interaction_id = ct.interaction_id;

COMMENT ON VIEW v_call_tasks_as_scheduler_items IS 
'Compatibility view: call_tasks projected into scheduler_items schema via interactions join. Read-only for overlap/delta analysis.';
;
