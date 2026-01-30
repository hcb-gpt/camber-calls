
WITH duplicates AS (
    SELECT 
        id,
        interaction_id,
        ROW_NUMBER() OVER (
            PARTITION BY interaction_id 
            ORDER BY ingested_at_utc DESC NULLS LAST, id
        ) as rn
    FROM interactions
    WHERE interaction_id IN (
        SELECT interaction_id 
        FROM interactions 
        GROUP BY interaction_id 
        HAVING COUNT(*) > 1
    )
),
rows_to_move AS (
    SELECT id FROM duplicates WHERE rn > 1
)
INSERT INTO interactions_errors (
    interaction_id, channel, source_zap, owner_name, owner_phone,
    contact_name, contact_phone, thread_key, event_at_utc, event_at_local,
    ingested_at_utc, human_summary, ai_scheduler_json, future_proof_json,
    bug_flags_json, enrichment_conf, has_scheduler_items, scheduler_item_count,
    scheduler_schema_version, error_reason, original_id
)
SELECT 
    interaction_id, channel, source_zap, owner_name, owner_phone,
    contact_name, contact_phone, thread_key, event_at_utc, event_at_local,
    ingested_at_utc, human_summary, ai_scheduler_json, future_proof_json,
    bug_flags_json, enrichment_conf, has_scheduler_items, scheduler_item_count,
    scheduler_schema_version, 
    'duplicate_interaction_id_cleanup_v3' as error_reason,
    id as original_id
FROM interactions
WHERE id IN (SELECT id FROM rows_to_move);
;
