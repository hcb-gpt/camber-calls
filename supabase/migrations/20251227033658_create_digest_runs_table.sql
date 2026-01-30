
CREATE TABLE IF NOT EXISTS digest_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_at_utc      TIMESTAMPTZ NOT NULL DEFAULT now(),
    window_start_utc TIMESTAMPTZ NOT NULL,
    window_end_utc  TIMESTAMPTZ NOT NULL,
    channel         TEXT NOT NULL,
    recipient       TEXT,
    task_count      INTEGER,
    payload         JSONB NOT NULL,
    
    -- Channel enum check
    CONSTRAINT digest_runs_channel_check 
        CHECK (channel IN ('email', 'slack', 'sms', 'other'))
);

COMMENT ON TABLE digest_runs IS 'Audit log of digest sends with window and payload snapshot';

CREATE INDEX IF NOT EXISTS idx_digest_runs_run_at ON digest_runs(run_at_utc DESC);
CREATE INDEX IF NOT EXISTS idx_digest_runs_channel ON digest_runs(channel);
;
