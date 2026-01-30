-- span_attributions: Project attribution per span (supports multi-project calls)
CREATE TABLE span_attributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  span_id UUID NOT NULL REFERENCES conversation_spans(id) ON DELETE CASCADE,
  
  -- Attribution
  project_id UUID REFERENCES projects(id),
  confidence NUMERIC(4,3),  -- 0.000 to 1.000
  attribution_source TEXT,  -- 'transcript_scan', 'contact_link', 'manual', etc.
  
  -- Evidence
  matched_terms TEXT[],     -- Keywords that triggered attribution
  match_positions JSONB,    -- [{term, char_start, char_end}, ...]
  
  -- Audit
  attributed_at TIMESTAMPTZ DEFAULT NOW(),
  attributed_by TEXT DEFAULT 'pipeline',  -- 'pipeline', 'manual', 'review'
  
  UNIQUE(span_id, project_id)
);

-- Indexes
CREATE INDEX idx_span_attributions_span ON span_attributions(span_id);
CREATE INDEX idx_span_attributions_project ON span_attributions(project_id);

COMMENT ON TABLE span_attributions IS 'Per-span project attribution. Enables multi-project calls and segment-level accuracy tracking.';;
