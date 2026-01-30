-- Secure storage for API keys (accessible only via service role)
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service TEXT NOT NULL UNIQUE,
  api_key TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: No public access
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- No policies = only service role can access

-- Insert keys
INSERT INTO api_keys (service, api_key) VALUES
  ('deepgram', '2b5501e042795ea8ee5361d26af7e64a4b0ddb44'),
  ('assemblyai', '2c93c9e615a84a78b98b735ad8dce575');

COMMENT ON TABLE api_keys IS 'Secure API key storage - service role only';;
