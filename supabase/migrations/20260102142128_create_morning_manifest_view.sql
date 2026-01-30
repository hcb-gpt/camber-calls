
-- Morning Manifest view: yesterday's conversations → today's work
CREATE OR REPLACE VIEW v_morning_manifest AS
SELECT 
    si.id as task_id,
    si.title,
    si.assignee,
    si.due_at_utc,
    si.status,
    si.meta->>'priority' as priority,
    COALESCE((si.meta->>'was_edited')::boolean, false) as was_edited,
    si.meta->>'skip_reason' as skip_reason,
    si.created_at as task_created,
    i.interaction_id,
    i.human_summary,
    i.contact_name,
    i.contact_phone,
    c.company as contact_company,
    c.trade as contact_trade,
    i.event_at_utc as call_time,
    i.channel
FROM scheduler_items si
JOIN interactions i ON si.interaction_id = i.id
LEFT JOIN contacts c ON c.phone = i.contact_phone
WHERE si.status = 'pending'
ORDER BY 
    si.due_at_utc NULLS LAST, 
    si.created_at DESC;

COMMENT ON VIEW v_morning_manifest IS 
'Daily review surface: pending tasks with call context. Query with task_created filter for time windows.';
;
