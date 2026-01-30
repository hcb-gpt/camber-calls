
-- Gate 4: Journal Tables Schema
-- Created: 2026-01-19
-- Contract: GATE4_Journal_Write_Contract_v1.md

-- ============================================
-- 1. journal_runs (Audit Table - create first for FK)
-- ============================================
CREATE TABLE journal_runs (
  run_id UUID PRIMARY KEY,
  call_id TEXT NOT NULL,
  project_id UUID,

  -- Run metadata
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  status TEXT DEFAULT 'running' CHECK (status IN ('running', 'success', 'failed')),

  -- Stats
  claims_extracted INTEGER DEFAULT 0,
  conflicts_detected INTEGER DEFAULT 0,
  routed_to_review INTEGER DEFAULT 0,

  -- Error tracking
  error_message TEXT,

  -- Config snapshot
  config JSONB
);

CREATE INDEX idx_journal_runs_call ON journal_runs(call_id);
CREATE INDEX idx_journal_runs_status ON journal_runs(status);

-- ============================================
-- 2. journal_claims
-- ============================================
CREATE TABLE journal_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL,
  claim_id UUID NOT NULL DEFAULT gen_random_uuid(),
  call_id TEXT NOT NULL,
  project_id UUID NOT NULL,

  -- Claim content
  claim_type TEXT NOT NULL CHECK (claim_type IN (
    'commitment', 'deadline', 'decision', 'blocker',
    'requirement', 'preference', 'concern', 'fact',
    'question', 'update'
  )),
  claim_text TEXT NOT NULL,

  -- Temporal pointers
  start_sec NUMERIC,
  end_sec NUMERIC,

  -- Epistemic metadata
  epistemic_status TEXT NOT NULL CHECK (epistemic_status IN ('stated', 'inferred', 'uncertain')),
  warrant_level TEXT NOT NULL CHECK (warrant_level IN ('high', 'medium', 'low')),

  -- Relationship to prior claims
  relationship TEXT CHECK (relationship IN ('new', 'supersedes', 'corroborates', 'conflicts')),
  supersedes_claim_id UUID,

  -- Lifecycle
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Foreign keys
  CONSTRAINT fk_journal_claims_project FOREIGN KEY (project_id) REFERENCES projects(id),
  CONSTRAINT fk_journal_claims_run FOREIGN KEY (run_id) REFERENCES journal_runs(run_id)
);

CREATE INDEX idx_journal_claims_run ON journal_claims(run_id);
CREATE INDEX idx_journal_claims_project ON journal_claims(project_id);
CREATE INDEX idx_journal_claims_call ON journal_claims(call_id);
CREATE INDEX idx_journal_claims_active ON journal_claims(project_id, active) WHERE active = true;

-- ============================================
-- 3. journal_conflicts
-- ============================================
CREATE TABLE journal_conflicts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL,

  claim_a_id UUID NOT NULL,
  claim_b_id UUID NOT NULL,
  conflict_type TEXT NOT NULL,

  resolved BOOLEAN DEFAULT false,
  resolution_notes TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT fk_journal_conflicts_run FOREIGN KEY (run_id) REFERENCES journal_runs(run_id)
);

CREATE INDEX idx_journal_conflicts_run ON journal_conflicts(run_id);
CREATE INDEX idx_journal_conflicts_unresolved ON journal_conflicts(resolved) WHERE resolved = false;

-- ============================================
-- 4. journal_open_loops
-- ============================================
CREATE TABLE journal_open_loops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL,
  call_id TEXT NOT NULL,
  project_id UUID,

  loop_type TEXT NOT NULL CHECK (loop_type IN ('question', 'blocker', 'follow_up', 'action_item')),
  description TEXT NOT NULL,

  -- Optional pointer
  start_sec NUMERIC,
  end_sec NUMERIC,

  -- Status
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'closed', 'stale')),

  created_at TIMESTAMPTZ DEFAULT NOW(),
  closed_at TIMESTAMPTZ,

  CONSTRAINT fk_journal_open_loops_run FOREIGN KEY (run_id) REFERENCES journal_runs(run_id)
);

CREATE INDEX idx_journal_open_loops_run ON journal_open_loops(run_id);
CREATE INDEX idx_journal_open_loops_project ON journal_open_loops(project_id);
CREATE INDEX idx_journal_open_loops_open ON journal_open_loops(status) WHERE status = 'open';

-- ============================================
-- 5. journal_review_queue
-- ============================================
CREATE TABLE journal_review_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL,

  item_type TEXT NOT NULL,
  item_id UUID,
  reason TEXT NOT NULL,

  data JSONB NOT NULL,

  -- Review status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'modified')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  review_notes TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT fk_journal_review_queue_run FOREIGN KEY (run_id) REFERENCES journal_runs(run_id)
);

CREATE INDEX idx_journal_review_queue_run ON journal_review_queue(run_id);
CREATE INDEX idx_journal_review_queue_pending ON journal_review_queue(status) WHERE status = 'pending';
CREATE INDEX idx_journal_review_queue_type ON journal_review_queue(item_type);
;
