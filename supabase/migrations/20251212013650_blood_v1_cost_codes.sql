
-- blood_v1: Cost codes reference table
-- Canonical cost code structure for Heartwood

CREATE TABLE cost_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cost_code_number TEXT NOT NULL UNIQUE,
  cost_code_name TEXT NOT NULL,
  division TEXT,  -- e.g., 'PRE-CONSTRUCTION', 'FRAMING', 'EXTERIOR'
  phase_sequence INTEGER,  -- ordering for construction phases
  cost_code_keywords JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE cost_codes IS 'blood_v1: Cost code taxonomy with keywords for inference matching';
COMMENT ON COLUMN cost_codes.cost_code_keywords IS 'Keywords that signal this cost code on invoices/transcripts';
COMMENT ON COLUMN cost_codes.phase_sequence IS 'Numeric order in construction sequence for phase inference';
;
