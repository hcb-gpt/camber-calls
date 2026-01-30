
-- Migrate unique call_tasks to scheduler_items
INSERT INTO scheduler_items (
    id,
    interaction_id,
    item_type,
    title,
    description,
    time_hint,
    start_at_utc,
    due_at_utc,
    assignee,
    status,
    financial_json,
    scheduler_schema_version,
    created_at,
    updated_at,
    payload,
    meta,
    source,
    item_hash
)
SELECT 
    gen_random_uuid() as id,
    i.id as interaction_id,
    'task' as item_type,
    ct.task_text as title,
    NULL as description,
    NULL as time_hint,
    NULL as start_at_utc,
    CASE WHEN ct.due_date IS NOT NULL 
         THEN ct.due_date::timestamp AT TIME ZONE 'America/New_York' AT TIME ZONE 'UTC'
         ELSE NULL 
    END as due_at_utc,
    ct.owner as assignee,
    'pending' as status,
    NULL as financial_json,
    2 as scheduler_schema_version,
    ct.created_at_utc as created_at,
    ct.updated_at_utc as updated_at,
    NULL as payload,
    jsonb_build_object(
        'migrated_from', 'call_tasks',
        'migration_date', '2026-01-02',
        'original_id', ct.id::text,
        'priority', ct.priority
    ) as meta,
    ct.source as source,
    MD5(i.id::text || 'task' || ct.task_text) as item_hash
FROM call_tasks ct
JOIN interactions i ON i.interaction_id = ct.interaction_id
WHERE NOT EXISTS (
    SELECT 1 FROM scheduler_items si 
    WHERE si.interaction_id = i.id 
    AND LOWER(TRIM(si.title)) = LOWER(TRIM(ct.task_text))
);
;
