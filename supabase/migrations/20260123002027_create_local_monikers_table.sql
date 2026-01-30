-- Local Monikers Table (v0.1)
-- Purpose: Geographic, subdivision, and project nickname aliases for candidate expansion
-- Contract: Monikers can ADD candidates but cannot SELECT without project-binding evidence

CREATE TABLE IF NOT EXISTS local_monikers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- The moniker text (what appears in transcripts)
  moniker TEXT NOT NULL,
  moniker_normalized TEXT GENERATED ALWAYS AS (LOWER(TRIM(moniker))) STORED,
  
  -- Type classification
  moniker_type TEXT NOT NULL CHECK (moniker_type IN (
    'geographic',           -- city, county, region ("Madison", "Morgan County", "Lake Oconee")
    'subdivision',          -- community/subdivision ("Reynolds", "Harbor Club", "Cuscowilla")
    'project_nickname',     -- stable nickname mapping to single project ("the lake house", "Skelton job")
    'landmark'              -- local landmarks ("the lake", "town square")
  )),
  
  -- Project binding (NULL = expands to multiple, non-NULL = direct map)
  project_id UUID REFERENCES projects(id),
  
  -- For geographic monikers that expand to multiple projects
  -- e.g., "Madison" expands to all projects WHERE city = 'Madison'
  expansion_rule JSONB,  -- e.g., {"city": "Madison"} or {"subdivision": "Reynolds"}
  
  -- Disambiguation requirements
  requires_binding_evidence BOOLEAN DEFAULT TRUE,
  disambiguation_notes TEXT,
  
  -- Confidence and source
  confidence NUMERIC(3,2) DEFAULT 0.80 CHECK (confidence BETWEEN 0 AND 1),
  source TEXT,  -- 'manual', 'auto_trigger', 'backfill'
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  UNIQUE (moniker_normalized, moniker_type)
);

-- Index for fast lookup during transcript scanning
CREATE INDEX IF NOT EXISTS idx_local_monikers_normalized ON local_monikers(moniker_normalized);
CREATE INDEX IF NOT EXISTS idx_local_monikers_type ON local_monikers(moniker_type);
CREATE INDEX IF NOT EXISTS idx_local_monikers_project ON local_monikers(project_id) WHERE project_id IS NOT NULL;

-- Comment
COMMENT ON TABLE local_monikers IS 'Local moniker lexicon for candidate expansion. Per STRAT v0.1 contract: monikers can ADD candidates but cannot SELECT without project-binding evidence. Reputational tags live in receipts only.';
COMMENT ON COLUMN local_monikers.requires_binding_evidence IS 'If TRUE, this moniker alone cannot select a project; needs homeowner name, address fragment, or single-project contact constraint.';
COMMENT ON COLUMN local_monikers.expansion_rule IS 'JSON rule for expanding to multiple projects, e.g., {"city": "Madison"} matches all projects with that city.';;
