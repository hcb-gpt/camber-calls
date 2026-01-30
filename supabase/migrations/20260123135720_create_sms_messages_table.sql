
-- SMS messages table for CAMBER ingestion
-- Minimal schema matching CSV export structure
CREATE TABLE IF NOT EXISTS sms_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id TEXT UNIQUE NOT NULL,          -- original chat message ID
  thread_id TEXT NOT NULL,                   -- chat_id from CSV (conversation thread)
  sender_inbox_id TEXT,                      -- inbox identifier
  sender_user_id TEXT NOT NULL,              -- user who sent message
  sent_at TIMESTAMPTZ NOT NULL,              -- created_at from CSV
  content TEXT,                              -- message text
  ingested_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Derived fields for query convenience
  direction TEXT,                            -- 'inbound' or 'outbound' relative to HCB
  contact_name TEXT,                         -- resolved contact name
  contact_phone TEXT                         -- resolved contact phone
);

CREATE INDEX idx_sms_thread_id ON sms_messages(thread_id);
CREATE INDEX idx_sms_sender_user_id ON sms_messages(sender_user_id);
CREATE INDEX idx_sms_sent_at ON sms_messages(sent_at);
CREATE INDEX idx_sms_contact_name ON sms_messages(contact_name);
;
