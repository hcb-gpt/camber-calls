
-- Migration: create_backfill_scheduler_items_function
-- Purpose: Idempotent unpacking of ai_scheduler_json into scheduler_items

CREATE OR REPLACE FUNCTION backfill_scheduler_items(p_dry_run BOOLEAN DEFAULT TRUE)
RETURNS TABLE (
  interaction_id TEXT,
  items_found INT,
  items_inserted INT,
  items_skipped INT
) AS $$
DECLARE
  v_interaction RECORD;
  v_item RECORD;
  v_item_hash TEXT;
  v_item_type TEXT;
  v_title TEXT;
  v_description TEXT;
  v_assignee TEXT;
  v_payload JSONB;
  v_found INT;
  v_inserted INT;
  v_skipped INT;
BEGIN
  FOR v_interaction IN 
    SELECT 
      i.id AS uuid_id,
      i.interaction_id AS text_id,
      i.ai_scheduler_json
    FROM interactions i
    WHERE i.ai_scheduler_json IS NOT NULL
      AND jsonb_typeof(i.ai_scheduler_json) = 'object'
  LOOP
    v_found := 0;
    v_inserted := 0;
    v_skipped := 0;
    
    -- Process tasks array
    IF v_interaction.ai_scheduler_json ? 'tasks' 
       AND jsonb_typeof(v_interaction.ai_scheduler_json->'tasks') = 'array' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_interaction.ai_scheduler_json->'tasks')
      LOOP
        v_found := v_found + 1;
        v_item_type := 'task';
        v_title := COALESCE(v_item.value->>'title', v_item.value->>'description', 'Untitled Task');
        v_description := COALESCE(v_item.value->>'details', v_item.value->>'notes', v_item.value->>'description');
        v_assignee := v_item.value->>'assignee';
        v_payload := v_item.value;
        v_item_hash := md5(v_interaction.uuid_id::text || v_item_type || v_title);
        
        IF NOT p_dry_run THEN
          INSERT INTO scheduler_items (
            interaction_id, item_type, title, description, assignee, 
            status, source, payload, item_hash, meta
          ) VALUES (
            v_interaction.uuid_id, v_item_type, v_title, v_description, v_assignee,
            'pending', 'backfill', v_payload, v_item_hash, 
            jsonb_build_object('source_array', 'tasks', 'backfill_ts', now())
          )
          ON CONFLICT (interaction_id, item_hash) DO NOTHING;
          
          IF FOUND THEN v_inserted := v_inserted + 1;
          ELSE v_skipped := v_skipped + 1;
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM scheduler_items WHERE interaction_id = v_interaction.uuid_id AND item_hash = v_item_hash) THEN
            v_skipped := v_skipped + 1;
          ELSE
            v_inserted := v_inserted + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    -- Process events array
    IF v_interaction.ai_scheduler_json ? 'events' 
       AND jsonb_typeof(v_interaction.ai_scheduler_json->'events') = 'array' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_interaction.ai_scheduler_json->'events')
      LOOP
        v_found := v_found + 1;
        v_item_type := 'event';
        v_title := COALESCE(v_item.value->>'title', v_item.value->>'description', 'Untitled Event');
        v_description := COALESCE(v_item.value->>'details', v_item.value->>'notes');
        v_assignee := v_item.value->>'assignee';
        v_payload := v_item.value;
        v_item_hash := md5(v_interaction.uuid_id::text || v_item_type || v_title);
        
        IF NOT p_dry_run THEN
          INSERT INTO scheduler_items (
            interaction_id, item_type, title, description, assignee,
            status, source, payload, item_hash, meta
          ) VALUES (
            v_interaction.uuid_id, v_item_type, v_title, v_description, v_assignee,
            'pending', 'backfill', v_payload, v_item_hash,
            jsonb_build_object('source_array', 'events', 'backfill_ts', now())
          )
          ON CONFLICT (interaction_id, item_hash) DO NOTHING;
          
          IF FOUND THEN v_inserted := v_inserted + 1;
          ELSE v_skipped := v_skipped + 1;
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM scheduler_items WHERE interaction_id = v_interaction.uuid_id AND item_hash = v_item_hash) THEN
            v_skipped := v_skipped + 1;
          ELSE
            v_inserted := v_inserted + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    -- Process deadlines array
    IF v_interaction.ai_scheduler_json ? 'deadlines' 
       AND jsonb_typeof(v_interaction.ai_scheduler_json->'deadlines') = 'array' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_interaction.ai_scheduler_json->'deadlines')
      LOOP
        v_found := v_found + 1;
        v_item_type := 'deadline';
        v_title := COALESCE(v_item.value->>'title', v_item.value->>'description', 'Untitled Deadline');
        v_description := COALESCE(v_item.value->>'details', v_item.value->>'notes');
        v_assignee := v_item.value->>'assignee';
        v_payload := v_item.value;
        v_item_hash := md5(v_interaction.uuid_id::text || v_item_type || v_title);
        
        IF NOT p_dry_run THEN
          INSERT INTO scheduler_items (
            interaction_id, item_type, title, description, assignee,
            status, source, payload, item_hash, meta
          ) VALUES (
            v_interaction.uuid_id, v_item_type, v_title, v_description, v_assignee,
            'pending', 'backfill', v_payload, v_item_hash,
            jsonb_build_object('source_array', 'deadlines', 'backfill_ts', now())
          )
          ON CONFLICT (interaction_id, item_hash) DO NOTHING;
          
          IF FOUND THEN v_inserted := v_inserted + 1;
          ELSE v_skipped := v_skipped + 1;
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM scheduler_items WHERE interaction_id = v_interaction.uuid_id AND item_hash = v_item_hash) THEN
            v_skipped := v_skipped + 1;
          ELSE
            v_inserted := v_inserted + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    -- Process follow_ups array
    IF v_interaction.ai_scheduler_json ? 'follow_ups' 
       AND jsonb_typeof(v_interaction.ai_scheduler_json->'follow_ups') = 'array' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_interaction.ai_scheduler_json->'follow_ups')
      LOOP
        v_found := v_found + 1;
        v_item_type := 'follow_up';
        v_title := COALESCE(
          v_item.value->>'title', 
          v_item.value->>'action',
          v_item.value->>'type',
          v_item.value->>'details',
          'Follow-up'
        );
        v_description := COALESCE(v_item.value->>'details', v_item.value->>'notes');
        v_assignee := COALESCE(v_item.value->>'assignee', v_item.value->>'owner');
        v_payload := v_item.value;
        v_item_hash := md5(v_interaction.uuid_id::text || v_item_type || v_title);
        
        IF NOT p_dry_run THEN
          INSERT INTO scheduler_items (
            interaction_id, item_type, title, description, assignee,
            status, source, payload, item_hash, meta
          ) VALUES (
            v_interaction.uuid_id, v_item_type, v_title, v_description, v_assignee,
            'pending', 'backfill', v_payload, v_item_hash,
            jsonb_build_object('source_array', 'follow_ups', 'backfill_ts', now())
          )
          ON CONFLICT (interaction_id, item_hash) DO NOTHING;
          
          IF FOUND THEN v_inserted := v_inserted + 1;
          ELSE v_skipped := v_skipped + 1;
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM scheduler_items WHERE interaction_id = v_interaction.uuid_id AND item_hash = v_item_hash) THEN
            v_skipped := v_skipped + 1;
          ELSE
            v_inserted := v_inserted + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    -- Process reminders array
    IF v_interaction.ai_scheduler_json ? 'reminders' 
       AND jsonb_typeof(v_interaction.ai_scheduler_json->'reminders') = 'array' THEN
      FOR v_item IN SELECT * FROM jsonb_array_elements(v_interaction.ai_scheduler_json->'reminders')
      LOOP
        v_found := v_found + 1;
        v_item_type := 'other';
        v_title := COALESCE(v_item.value->>'title', v_item.value->>'description', 'Reminder');
        v_description := COALESCE(v_item.value->>'details', v_item.value->>'notes');
        v_assignee := v_item.value->>'assignee';
        v_payload := v_item.value;
        v_item_hash := md5(v_interaction.uuid_id::text || v_item_type || v_title);
        
        IF NOT p_dry_run THEN
          INSERT INTO scheduler_items (
            interaction_id, item_type, title, description, assignee,
            status, source, payload, item_hash, meta
          ) VALUES (
            v_interaction.uuid_id, v_item_type, v_title, v_description, v_assignee,
            'pending', 'backfill', v_payload, v_item_hash,
            jsonb_build_object('source_array', 'reminders', 'backfill_ts', now())
          )
          ON CONFLICT (interaction_id, item_hash) DO NOTHING;
          
          IF FOUND THEN v_inserted := v_inserted + 1;
          ELSE v_skipped := v_skipped + 1;
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM scheduler_items WHERE interaction_id = v_interaction.uuid_id AND item_hash = v_item_hash) THEN
            v_skipped := v_skipped + 1;
          ELSE
            v_inserted := v_inserted + 1;
          END IF;
        END IF;
      END LOOP;
    END IF;
    
    IF v_found > 0 THEN
      interaction_id := v_interaction.text_id;
      items_found := v_found;
      items_inserted := v_inserted;
      items_skipped := v_skipped;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION backfill_scheduler_items IS 
'Idempotent backfill of scheduler_items from interactions.ai_scheduler_json. 
Pass p_dry_run=TRUE (default) to preview, FALSE to execute.
Uses MD5(interaction_id + item_type + title) for deduplication.';
;
