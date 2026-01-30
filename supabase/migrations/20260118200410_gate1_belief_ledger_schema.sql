
-- ============================================
-- GATE 1: Belief Ledger Schema Migration
-- Per frozen interface v1.1
-- ============================================

-- ENUMS
CREATE TYPE claim_type_enum AS ENUM (
  'state', 'event', 'decision', 'commitment', 'request', 'risk', 'open_loop'
);

CREATE TYPE epistemic_status_enum AS ENUM (
  'observed', 'reported', 'inferred', 'promised', 'decided', 'disputed', 'superseded'
);

CREATE TYPE warrant_level_enum AS ENUM (
  'planning_accept', 'execution_accept'
);

CREATE TYPE origin_kind_enum AS ENUM (
  'firsthand', 'secondhand', 'world_contact', 'unknown'
);

CREATE TYPE conflict_type_enum AS ENUM (
  'factual', 'temporal', 'commitment'
);

CREATE TYPE conflict_status_enum AS ENUM (
  'unresolved', 'resolved', 'superseded'
);

CREATE TYPE lifecycle_enum AS ENUM (
  'active', 'superseded', 'resolved', 'disputed'
);

CREATE TYPE loop_status_enum AS ENUM (
  'open', 'done', 'overdue'
);

CREATE TYPE source_type_enum AS ENUM (
  'transcript_audio', 'transcript_text', 'photo', 'doc', 'system_record'
);

CREATE TYPE adapter_status_enum AS ENUM (
  'active', 'partial', 'not_integrated', 'error'
);

-- CORE TABLE: belief_claims
CREATE TABLE belief_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_type claim_type_enum NOT NULL,
  epistemic_status epistemic_status_enum NOT NULL,
  warrant_level warrant_level_enum NOT NULL,
  confidence NUMERIC(3,2) NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  confidence_rationale VARCHAR(100) NOT NULL,
  lifecycle lifecycle_enum NOT NULL DEFAULT 'active',
  
  -- Subject refs
  project_id UUID NOT NULL REFERENCES projects(id),
  contact_id UUID REFERENCES contacts(id),
  vendor_id UUID,  -- No FK - vendors_v is a view
  
  -- Attribution
  speaker_entity_id UUID NOT NULL,
  origin_entity_id UUID,
  origin_kind origin_kind_enum NOT NULL,
  origin_confidence NUMERIC(3,2) CHECK (origin_confidence >= 0 AND origin_confidence <= 1),
  
  -- Bitemporal
  event_at_utc TIMESTAMPTZ NOT NULL,
  ingested_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Content
  short_text VARCHAR(240) NOT NULL,
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- POINTERS: claim_pointers
CREATE TABLE claim_pointers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id UUID NOT NULL REFERENCES belief_claims(id) ON DELETE CASCADE,
  source_type source_type_enum NOT NULL,
  source_id TEXT NOT NULL,
  ts_start NUMERIC,
  ts_end NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CONFLICTS: belief_conflicts
CREATE TABLE belief_conflicts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conflict_type conflict_type_enum NOT NULL,
  status conflict_status_enum NOT NULL DEFAULT 'unresolved',
  summary VARCHAR(240) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- JUNCTION: conflict_claims
CREATE TABLE conflict_claims (
  conflict_id UUID NOT NULL REFERENCES belief_conflicts(id) ON DELETE CASCADE,
  claim_id UUID NOT NULL REFERENCES belief_claims(id) ON DELETE CASCADE,
  PRIMARY KEY (conflict_id, claim_id)
);

-- ASSUMPTIONS: belief_assumptions
CREATE TABLE belief_assumptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  selected_claim_id UUID NOT NULL REFERENCES belief_claims(id),
  conflict_id UUID REFERENCES belief_conflicts(id),
  scope VARCHAR(20) NOT NULL DEFAULT 'planning' CHECK (scope = 'planning'),
  ttl_utc TIMESTAMPTZ NOT NULL,
  rationale VARCHAR(240) NOT NULL,
  created_by UUID NOT NULL,
  created_at_utc TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- OPEN LOOPS: belief_open_loops
CREATE TABLE belief_open_loops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id),
  owner_entity_id UUID NOT NULL,
  due_date DATE,
  status loop_status_enum NOT NULL DEFAULT 'open',
  summary VARCHAR(240) NOT NULL,
  event_at_utc TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- OPEN LOOP POINTERS: loop_pointers
CREATE TABLE loop_pointers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loop_id UUID NOT NULL REFERENCES belief_open_loops(id) ON DELETE CASCADE,
  source_type source_type_enum NOT NULL,
  source_id TEXT NOT NULL,
  ts_start NUMERIC,
  ts_end NUMERIC,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ADAPTER STATUS: adapter_status
CREATE TABLE adapter_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  adapter_name VARCHAR(50) NOT NULL UNIQUE,
  status adapter_status_enum NOT NULL DEFAULT 'not_integrated',
  last_sync_utc TIMESTAMPTZ,
  config_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- INDEXES
CREATE INDEX idx_belief_claims_project ON belief_claims(project_id);
CREATE INDEX idx_belief_claims_lifecycle ON belief_claims(lifecycle);
CREATE INDEX idx_belief_claims_event_at ON belief_claims(event_at_utc DESC);
CREATE INDEX idx_belief_claims_confidence ON belief_claims(confidence DESC);
CREATE INDEX idx_claim_pointers_claim ON claim_pointers(claim_id);
CREATE INDEX idx_claim_pointers_source ON claim_pointers(source_id);
CREATE INDEX idx_conflict_claims_claim ON conflict_claims(claim_id);
CREATE INDEX idx_belief_open_loops_project ON belief_open_loops(project_id);
CREATE INDEX idx_belief_open_loops_status ON belief_open_loops(status);
CREATE INDEX idx_belief_open_loops_due ON belief_open_loops(due_date);

-- Seed adapter_status
INSERT INTO adapter_status (adapter_name, status, last_sync_utc) VALUES
  ('openphone', 'active', NOW()),
  ('buildertrend', 'not_integrated', NULL),
  ('google_drive', 'partial', NULL),
  ('email', 'not_integrated', NULL);

-- RLS (enable but permissive for now)
ALTER TABLE belief_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE claim_pointers ENABLE ROW LEVEL SECURITY;
ALTER TABLE belief_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE conflict_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE belief_assumptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE belief_open_loops ENABLE ROW LEVEL SECURITY;
ALTER TABLE loop_pointers ENABLE ROW LEVEL SECURITY;
ALTER TABLE adapter_status ENABLE ROW LEVEL SECURITY;

-- Permissive policies for service role
CREATE POLICY "Service role full access" ON belief_claims FOR ALL USING (true);
CREATE POLICY "Service role full access" ON claim_pointers FOR ALL USING (true);
CREATE POLICY "Service role full access" ON belief_conflicts FOR ALL USING (true);
CREATE POLICY "Service role full access" ON conflict_claims FOR ALL USING (true);
CREATE POLICY "Service role full access" ON belief_assumptions FOR ALL USING (true);
CREATE POLICY "Service role full access" ON belief_open_loops FOR ALL USING (true);
CREATE POLICY "Service role full access" ON loop_pointers FOR ALL USING (true);
CREATE POLICY "Service role full access" ON adapter_status FOR ALL USING (true);
;
