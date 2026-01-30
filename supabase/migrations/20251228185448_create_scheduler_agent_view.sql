
-- Create view for scheduler agent queries
DROP VIEW IF EXISTS v_scheduler_agent_items;

CREATE VIEW v_scheduler_agent_items AS
SELECT 
    s.id,
    s.interaction_id,
    i.interaction_id as interaction_text_id,
    s.item_type,
    s.title,
    s.description,
    s.time_hint,
    s.start_at_utc,
    s.due_at_utc,
    s.assignee,
    s.status,
    s.source,
    s.item_hash,
    s.created_at,
    s.updated_at,
    i.channel as interaction_channel,
    i.contact_name,
    i.contact_phone,
    i.owner_name,
    i.human_summary as interaction_summary,
    i.event_at_utc as interaction_timestamp,
    s.financial_json,
    i.financial_json as interaction_financial_json,
    s.payload
FROM scheduler_items s
JOIN interactions i ON i.id = s.interaction_id;

COMMENT ON VIEW v_scheduler_agent_items IS 
'Flattened scheduler items with interaction context for agent consumption.';
;
