-- GT Segments: Segment-level ground truth for multi-project calls
-- Replaces call-level truth model per STRAT22 directive (2026-01-26)
-- "Attribution is claim-level (optionally segment-level), not call-level."

CREATE TABLE IF NOT EXISTS ground_truth_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Source reference
  call_id TEXT NOT NULL,  -- interaction_id (cll_*)
  batch_id TEXT,          -- Golden batch identifier
  
  -- Segment boundaries
  segment_index INTEGER NOT NULL DEFAULT 0,  -- Order within call (0 = first segment)
  char_start INTEGER,     -- Character offset start
  char_end INTEGER,       -- Character offset end
  line_start INTEGER,     -- Line number start (for paper markup)
  line_end INTEGER,       -- Line number end
  
  -- Thread attribution (BEFORE/AFTER for switch tags)
  thread_before TEXT,     -- Thread attribution before this segment
  thread_after TEXT,      -- Thread attribution after this segment (the "current" thread)
  project_id UUID,        -- FK to projects if resolvable
  project_name TEXT,      -- Human label (may not match projects.name exactly)
  
  -- Turn type tag (from GT legend v1.1)
  turn_type TEXT CHECK (turn_type IN (
    'PF',   -- Predicate First / Missing Referent
    'CS',   -- Company Switch
    'PS',   -- Project Switch
    'TS',   -- Topic Switch
    'SS',   -- Sub-Switch
    'VS',   -- Variance / Conflict Signal
    'LL',   -- Long-Lead Lens
    'AU',   -- Access Update
    'EU',   -- Expectation Update
    'FU',   -- Financial Update
    'TAS',  -- Task Switch
    'TRS',  -- Trace Switch (reference to prior artifacts)
    'DEC',  -- Decision
    'COM',  -- Commitment
    'REQ',  -- Requirement / Request
    'DL',   -- Deadline
    'BLK',  -- Blocker
    'RSK',  -- Risk / Concern
    'Q',    -- Question
    'PREF', -- Preference
    'FACT', -- Fact
    'ASR',  -- Transcript failure / ASR error
    'ENT?'  -- Entity ambiguity
  )),
  
  -- For PF tags
  pre_anchor_end_line INTEGER,  -- Line where first anchor noun appears
  anchor_token TEXT,            -- The noun/name that grounds the thread
  
  -- Evidence
  evidence_span TEXT,    -- Raw span text from transcript
  entity_keywords TEXT[], -- Entity keywords mentioned
  
  -- Quality / confidence
  confidence TEXT CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW', 'AMBIGUOUS')),
  
  -- Provenance
  labeler TEXT DEFAULT 'CHAD',
  label_date TIMESTAMPTZ DEFAULT now(),
  notes TEXT,
  
  -- Constraints
  UNIQUE (call_id, segment_index, turn_type)
);

-- Index for efficient lookup
CREATE INDEX idx_gt_segments_call_id ON ground_truth_segments(call_id);
CREATE INDEX idx_gt_segments_batch_id ON ground_truth_segments(batch_id);
CREATE INDEX idx_gt_segments_project_id ON ground_truth_segments(project_id);
CREATE INDEX idx_gt_segments_turn_type ON ground_truth_segments(turn_type);

-- Comment
COMMENT ON TABLE ground_truth_segments IS 
'Segment-level ground truth for multi-project calls. Replaces call-level ground_truth_labels for attribution accuracy. Per STRAT22 directive: "Attribution is claim-level (optionally segment-level), not call-level."';

COMMENT ON COLUMN ground_truth_segments.thread_before IS 'Thread attribution BEFORE this segment (required for CS/PS/TS switch tags)';
COMMENT ON COLUMN ground_truth_segments.thread_after IS 'Thread attribution AFTER this segment (the current active thread)';;
