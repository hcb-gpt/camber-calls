-- ============================================================
-- CONSTRUCTION PHASES: Chronological Build Stages
-- ============================================================
-- These are the 10 phases of residential construction that 
-- align with the Gantt chart and cost code taxonomy.
-- 
-- Note: This is DIFFERENT from projects.phase which tracks
-- project STATUS (active, closed, etc.)
-- ============================================================

CREATE TABLE construction_phases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Code fields (matches cost_code_taxonomy pattern)
  code CHAR(4) NOT NULL UNIQUE,           -- '0000', '1000', etc.
  code_int INTEGER NOT NULL UNIQUE,       -- 0, 1000, etc. for sorting
  
  -- Display fields
  name TEXT NOT NULL,                     -- 'OVERHEAD & JOBSITE SUPPORT'
  display TEXT NOT NULL,                  -- '0000 - OVERHEAD & JOBSITE SUPPORT'
  short_name TEXT,                        -- 'Overhead', 'Pre-Con', etc.
  
  -- Metadata
  description TEXT,                       -- Detailed description
  sequence INTEGER NOT NULL UNIQUE,       -- 0-9 for ordering
  
  -- Phase characteristics
  is_spanning BOOLEAN DEFAULT FALSE,      -- True for 0000 and 9000 (span entire project)
  typical_duration_weeks INTEGER,         -- Typical duration in weeks
  milestone_name TEXT,                    -- Key milestone at phase end (e.g., 'Dry-In')
  
  -- Keywords for matching
  keywords TEXT[],                        -- Keywords for transcript/claim matching
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for common queries
CREATE INDEX idx_construction_phases_sequence ON construction_phases(sequence);
CREATE INDEX idx_construction_phases_code_int ON construction_phases(code_int);

-- Comment
COMMENT ON TABLE construction_phases IS 'Chronological construction phases (0000-9000) aligned with cost code taxonomy. Different from projects.phase which tracks project status.';
COMMENT ON COLUMN construction_phases.is_spanning IS 'True for phases that span the entire project (Overhead 0000, Closeout 9000)';
COMMENT ON COLUMN construction_phases.milestone_name IS 'Key milestone achieved at end of this phase';;
