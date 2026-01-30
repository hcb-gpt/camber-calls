
CREATE TABLE IF NOT EXISTS pipeline_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id      TEXT NOT NULL,
    channel             TEXT NOT NULL,
    zap_version         TEXT,
    event_at_utc        TIMESTAMPTZ,
    event_at_local      TIMESTAMPTZ,
    log_level           TEXT DEFAULT 'info',
    bug_flags_json      JSONB,
    future_proof_json   JSONB,
    logged_at_utc       TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE pipeline_logs IS 'Telemetry/audit log for pipeline runs (replaces calls_logs sheet)';

CREATE INDEX IF NOT EXISTS idx_pipeline_logs_interaction ON pipeline_logs(interaction_id);
CREATE INDEX IF NOT EXISTS idx_pipeline_logs_logged_at ON pipeline_logs(logged_at_utc DESC);
CREATE INDEX IF NOT EXISTS idx_pipeline_logs_channel ON pipeline_logs(channel);
;
