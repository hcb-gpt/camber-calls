
CREATE TABLE IF NOT EXISTS pipeline_config (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope           TEXT NOT NULL,
    config_key      TEXT NOT NULL,
    config_value    JSONB NOT NULL,
    description     TEXT,
    updated_by      TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE(scope, config_key)
);

COMMENT ON TABLE pipeline_config IS 'Scope-based config for call/sms/email pipelines (replaces calls_config sheet)';
;
