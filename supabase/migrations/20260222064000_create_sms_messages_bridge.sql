-- Bridge SMS message ingestion into canonical interaction surfaces.
-- This ensures sms_messages writes produce matching calls_raw + interactions rows.

CREATE OR REPLACE FUNCTION public.bridge_sms_message_to_surfaces()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_interaction_id text;
  v_ingested_at_utc timestamptz;
BEGIN
  v_interaction_id := 'sms_' || COALESCE(NULLIF(NEW.message_id, ''), NEW.id::text);
  v_ingested_at_utc := COALESCE(NEW.ingested_at, now());

  INSERT INTO public.calls_raw (
    interaction_id,
    channel,
    zap_version,
    thread_key,
    direction,
    other_party_name,
    other_party_phone,
    event_at_utc,
    summary,
    raw_snapshot_json,
    transcript,
    ingested_at_utc,
    inbox_id,
    source_received_at_utc,
    received_at_utc,
    capture_source,
    is_shadow
  )
  VALUES (
    v_interaction_id,
    'sms',
    'sms_bridge_v1',
    NEW.thread_id,
    NEW.direction,
    NEW.contact_name,
    NEW.contact_phone,
    COALESCE(NEW.sent_at, v_ingested_at_utc),
    left(COALESCE(NEW.content, ''), 280),
    to_jsonb(NEW),
    NEW.content,
    v_ingested_at_utc,
    NEW.sender_inbox_id,
    NEW.sent_at,
    v_ingested_at_utc,
    'sms_bridge_trigger',
    false
  )
  ON CONFLICT (interaction_id) DO UPDATE
  SET
    thread_key = EXCLUDED.thread_key,
    direction = EXCLUDED.direction,
    other_party_name = EXCLUDED.other_party_name,
    other_party_phone = EXCLUDED.other_party_phone,
    event_at_utc = EXCLUDED.event_at_utc,
    summary = EXCLUDED.summary,
    raw_snapshot_json = EXCLUDED.raw_snapshot_json,
    transcript = EXCLUDED.transcript,
    ingested_at_utc = EXCLUDED.ingested_at_utc,
    inbox_id = EXCLUDED.inbox_id,
    source_received_at_utc = EXCLUDED.source_received_at_utc,
    received_at_utc = EXCLUDED.received_at_utc,
    capture_source = EXCLUDED.capture_source;

  INSERT INTO public.interactions (
    interaction_id,
    channel,
    source_zap,
    contact_name,
    contact_phone,
    thread_key,
    event_at_utc,
    ingested_at_utc,
    human_summary,
    transcript_chars,
    is_shadow
  )
  VALUES (
    v_interaction_id,
    'sms',
    'sms_bridge_v1',
    NEW.contact_name,
    NEW.contact_phone,
    NEW.thread_id,
    COALESCE(NEW.sent_at, v_ingested_at_utc),
    v_ingested_at_utc,
    left(COALESCE(NEW.content, ''), 280),
    char_length(COALESCE(NEW.content, '')),
    false
  )
  ON CONFLICT (interaction_id) DO UPDATE
  SET
    contact_name = EXCLUDED.contact_name,
    contact_phone = EXCLUDED.contact_phone,
    thread_key = EXCLUDED.thread_key,
    event_at_utc = EXCLUDED.event_at_utc,
    ingested_at_utc = EXCLUDED.ingested_at_utc,
    human_summary = EXCLUDED.human_summary,
    transcript_chars = EXCLUDED.transcript_chars;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sms_messages_bridge_to_surfaces ON public.sms_messages;
CREATE TRIGGER trg_sms_messages_bridge_to_surfaces
AFTER INSERT OR UPDATE ON public.sms_messages
FOR EACH ROW
EXECUTE FUNCTION public.bridge_sms_message_to_surfaces();

-- Backfill existing SMS rows so downstream surfaces are populated immediately.
INSERT INTO public.calls_raw (
  interaction_id,
  channel,
  zap_version,
  thread_key,
  direction,
  other_party_name,
  other_party_phone,
  event_at_utc,
  summary,
  raw_snapshot_json,
  transcript,
  ingested_at_utc,
  inbox_id,
  source_received_at_utc,
  received_at_utc,
  capture_source,
  is_shadow
)
SELECT
  'sms_' || COALESCE(NULLIF(sm.message_id, ''), sm.id::text) AS interaction_id,
  'sms' AS channel,
  'sms_bridge_v1' AS zap_version,
  sm.thread_id AS thread_key,
  sm.direction,
  sm.contact_name AS other_party_name,
  sm.contact_phone AS other_party_phone,
  COALESCE(sm.sent_at, sm.ingested_at, now()) AS event_at_utc,
  left(COALESCE(sm.content, ''), 280) AS summary,
  to_jsonb(sm) AS raw_snapshot_json,
  sm.content AS transcript,
  COALESCE(sm.ingested_at, now()) AS ingested_at_utc,
  sm.sender_inbox_id AS inbox_id,
  sm.sent_at AS source_received_at_utc,
  COALESCE(sm.ingested_at, now()) AS received_at_utc,
  'sms_bridge_backfill_v1' AS capture_source,
  false AS is_shadow
FROM public.sms_messages sm
ON CONFLICT (interaction_id) DO NOTHING;

INSERT INTO public.interactions (
  interaction_id,
  channel,
  source_zap,
  contact_name,
  contact_phone,
  thread_key,
  event_at_utc,
  ingested_at_utc,
  human_summary,
  transcript_chars,
  is_shadow
)
SELECT
  'sms_' || COALESCE(NULLIF(sm.message_id, ''), sm.id::text) AS interaction_id,
  'sms' AS channel,
  'sms_bridge_v1' AS source_zap,
  sm.contact_name,
  sm.contact_phone,
  sm.thread_id AS thread_key,
  COALESCE(sm.sent_at, sm.ingested_at, now()) AS event_at_utc,
  COALESCE(sm.ingested_at, now()) AS ingested_at_utc,
  left(COALESCE(sm.content, ''), 280) AS human_summary,
  char_length(COALESCE(sm.content, '')) AS transcript_chars,
  false AS is_shadow
FROM public.sms_messages sm
ON CONFLICT (interaction_id) DO NOTHING;
