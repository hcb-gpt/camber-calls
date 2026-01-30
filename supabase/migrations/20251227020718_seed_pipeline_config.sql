
INSERT INTO pipeline_config (scope, config_key, config_value, description, updated_by)
VALUES (
    'call',
    'CALLS_SCHEDULER_NORMALIZE_V1',
    '{"enabled": true, "schema_version": 1, "test_mode": false}'::jsonb,
    'Normalize scheduler JSON output for calls pipeline v1',
    'DATA migration v3'
)
ON CONFLICT (scope, config_key) DO NOTHING;
;
