
CREATE TABLE IF NOT EXISTS calls_raw (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id      TEXT UNIQUE NOT NULL,
    channel             TEXT NOT NULL DEFAULT 'call',
    zap_version         TEXT,
    thread_key          TEXT,
    direction           TEXT,
    other_party_name    TEXT,
    other_party_phone   TEXT,
    owner_name          TEXT,
    owner_phone         TEXT,
    event_at_utc        TIMESTAMPTZ,
    event_at_local      TIMESTAMPTZ,
    summary             TEXT,
    raw_snapshot_json   JSONB,
    transcript          TEXT,
    bug_flags_json      JSONB,
    ingested_at_utc     TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE calls_raw IS 'Raw call archive with full transcript and raw_snapshot_json (replaces calls_raw sheet)';

CREATE INDEX IF NOT EXISTS idx_calls_raw_other_party_phone ON calls_raw(other_party_phone);
CREATE INDEX IF NOT EXISTS idx_calls_raw_ingested_at ON calls_raw(ingested_at_utc DESC);
CREATE INDEX IF NOT EXISTS idx_calls_raw_thread_key ON calls_raw(thread_key);
;
