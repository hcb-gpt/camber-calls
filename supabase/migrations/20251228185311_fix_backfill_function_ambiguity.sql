
-- Drop and recreate with fixed column names
DROP FUNCTION IF EXISTS backfill_scheduler_items();

CREATE OR REPLACE FUNCTION backfill_scheduler_items()
RETURNS TABLE(
    itx_id TEXT,
    inserted_count INT,
    skipped_count INT
) 
LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    json_data JSONB;
    item JSONB;
    item_type TEXT;
    arr_name TEXT;
    item_title TEXT;
    item_desc TEXT;
    item_assignee TEXT;
    item_time_hint TEXT;
    computed_hash TEXT;
    ins_count INT := 0;
    skip_count INT := 0;
    total_inserted INT := 0;
    total_skipped INT := 0;
BEGIN
    FOR rec IN 
        SELECT 
            i.id AS uuid_id,
            i.interaction_id AS text_id,
            i.ai_scheduler_json
        FROM interactions i
        WHERE i.ai_scheduler_json IS NOT NULL
    LOOP
        ins_count := 0;
        skip_count := 0;
        
        BEGIN
            json_data := CASE 
                WHEN jsonb_typeof(rec.ai_scheduler_json) = 'string' 
                THEN (rec.ai_scheduler_json #>> '{}')::jsonb
                ELSE rec.ai_scheduler_json
            END;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;
        
        FOREACH arr_name IN ARRAY ARRAY['tasks', 'events', 'deadlines', 'reminders', 'follow_ups']
        LOOP
            item_type := CASE arr_name
                WHEN 'tasks' THEN 'task'
                WHEN 'events' THEN 'event'
                WHEN 'deadlines' THEN 'deadline'
                WHEN 'reminders' THEN 'other'
                WHEN 'follow_ups' THEN 'follow_up'
            END;
            
            IF NOT (json_data ? arr_name) OR jsonb_array_length(COALESCE(json_data->arr_name, '[]'::jsonb)) = 0 THEN
                CONTINUE;
            END IF;
            
            FOR item IN SELECT * FROM jsonb_array_elements(json_data->arr_name)
            LOOP
                item_title := COALESCE(
                    item->>'title',
                    item->>'description',
                    item->>'task',
                    item->>'type',
                    'Untitled ' || item_type
                );
                
                item_desc := COALESCE(
                    item->>'details',
                    item->>'description',
                    item->>'notes'
                );
                
                item_assignee := COALESCE(
                    item->>'assignee',
                    item->>'owner'
                );
                
                item_time_hint := COALESCE(
                    item->>'due',
                    item->>'start',
                    item->>'datetime',
                    item->>'time',
                    item->>'recommended_timing'
                );
                
                computed_hash := md5(
                    rec.uuid_id::text || '|' || 
                    item_type || '|' || 
                    COALESCE(item_title, '')
                );
                
                INSERT INTO scheduler_items (
                    interaction_id,
                    item_type,
                    title,
                    description,
                    time_hint,
                    assignee,
                    status,
                    payload,
                    meta,
                    source,
                    item_hash
                ) VALUES (
                    rec.uuid_id,
                    item_type,
                    item_title,
                    item_desc,
                    item_time_hint,
                    item_assignee,
                    'pending',
                    item,
                    jsonb_build_object(
                        'source_array', arr_name,
                        'backfill_run', now()
                    ),
                    'ai',
                    computed_hash
                )
                ON CONFLICT (interaction_id, item_hash) DO NOTHING;
                
                IF FOUND THEN
                    ins_count := ins_count + 1;
                ELSE
                    skip_count := skip_count + 1;
                END IF;
            END LOOP;
        END LOOP;
        
        IF ins_count > 0 OR skip_count > 0 THEN
            itx_id := rec.text_id;
            inserted_count := ins_count;
            skipped_count := skip_count;
            RETURN NEXT;
        END IF;
        
        total_inserted := total_inserted + ins_count;
        total_skipped := total_skipped + skip_count;
    END LOOP;
    
    itx_id := '** TOTAL **';
    inserted_count := total_inserted;
    skipped_count := total_skipped;
    RETURN NEXT;
END;
$$;
;
