
-- Add Zapier-specific lineage columns per BESIDE-1 request
-- Minimal viable lineage: zapier_run_id, zapier_zap_id, zapier_account_id, inbox_id, received_at_utc

-- Check and add columns if not exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'zapier_run_id') THEN
    ALTER TABLE calls_raw ADD COLUMN zapier_run_id text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'zapier_zap_id') THEN
    ALTER TABLE calls_raw ADD COLUMN zapier_zap_id text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'zapier_account_id') THEN
    ALTER TABLE calls_raw ADD COLUMN zapier_account_id text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'inbox_id') THEN
    ALTER TABLE calls_raw ADD COLUMN inbox_id text;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'received_at_utc') THEN
    ALTER TABLE calls_raw ADD COLUMN received_at_utc timestamptz;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'calls_raw' AND column_name = 'capture_source') THEN
    ALTER TABLE calls_raw ADD COLUMN capture_source text;
  END IF;
END $$;

-- Add indexes for lineage queries
CREATE INDEX IF NOT EXISTS idx_calls_raw_zapier_run_id ON calls_raw(zapier_run_id) WHERE zapier_run_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_calls_raw_zapier_zap_id ON calls_raw(zapier_zap_id) WHERE zapier_zap_id IS NOT NULL;

COMMENT ON COLUMN calls_raw.zapier_run_id IS 'Zapier task history run ID for replay correlation';
COMMENT ON COLUMN calls_raw.zapier_zap_id IS 'Zapier Zap ID that processed this call';
COMMENT ON COLUMN calls_raw.zapier_account_id IS 'Zapier account ID for multi-account tracking';
COMMENT ON COLUMN calls_raw.inbox_id IS 'Beside inbox ID if available';
COMMENT ON COLUMN calls_raw.received_at_utc IS 'When Zapier received the webhook from Beside';
COMMENT ON COLUMN calls_raw.capture_source IS 'Originating system: beside, zapier_replay, pipedream_replay, manual';
;
