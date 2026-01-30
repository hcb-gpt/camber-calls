CREATE TABLE IF NOT EXISTS material_signal_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  term TEXT NOT NULL UNIQUE,
  aliases TEXT[] DEFAULT '{}',
  tier TEXT NOT NULL CHECK (tier IN ('stratospheric', 'extremely_high', 'high', 'medium', 'low')),
  boost NUMERIC(3,2) NOT NULL CHECK (boost >= 0 AND boost <= 1),
  notes TEXT,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_material_signal_config_active
  ON material_signal_config(active)
  WHERE active = TRUE;

COMMENT ON TABLE material_signal_config IS 'Config-driven material signal terms for attribution confidence boosting (Router v3.2.3).';

-- Seed data
INSERT INTO material_signal_config (term, aliases, tier, boost, notes) VALUES
('ipe deck', ARRAY['ipe', 'brazilian hardwood'], 'stratospheric', 0.20, 'Extremely rare, project-defining'),
('elevator', ARRAY['residential elevator', 'home elevator', 'lift'], 'extremely_high', 0.18, 'Rare luxury feature'),
('motorized screen', ARRAY['motorized screens'], 'high', 0.15, 'Luxury, currently Woodbery'),
('pool house', ARRAY['poolhouse'], 'high', 0.15, 'Likely only Hurley'),
('wine cellar', ARRAY['wine room'], 'high', 0.15, 'Luxury feature'),
('copper gutter', ARRAY['copper roof'], 'medium', 0.10, 'Somewhat specific'),
('bridge faucet', ARRAY[]::TEXT[], 'medium', 0.10, 'Somewhat specific'),
('dormer', ARRAY[]::TEXT[], 'medium', 0.10, 'Somewhat specific'),
('transom', ARRAY[]::TEXT[], 'medium', 0.10, 'Somewhat specific'),
('septic', ARRAY[]::TEXT[], 'low', 0.00, 'Rural Georgia ubiquitous'),
('board and batten', ARRAY[]::TEXT[], 'low', 0.00, 'Common Southern siding'),
('framing', ARRAY['frame', 'stud', '2x4', '2x6'], 'low', 0.00, 'Universal'),
('drywall', ARRAY['sheetrock'], 'low', 0.00, 'Universal'),
('fireplace', ARRAY[]::TEXT[], 'low', 0.00, 'Common across projects')
ON CONFLICT (term) DO NOTHING;;
