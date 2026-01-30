
-- spine_v1: Override/audit table for cost code assignments
-- Tracks when humans correct Gandalf's inferences

CREATE TABLE financial_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id UUID REFERENCES interactions(id) ON DELETE CASCADE,
  scheduler_item_id UUID,  -- FK added when scheduler_items table exists
  original_cost_code_id UUID REFERENCES cost_codes(id),
  override_cost_code_id UUID REFERENCES cost_codes(id),
  original_confidence DECIMAL(3,2),
  override_reason TEXT,
  overridden_by TEXT,  -- 'chad', 'zack', etc.
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_financial_overrides_interaction ON financial_overrides(interaction_id);
CREATE INDEX idx_financial_overrides_created ON financial_overrides(created_at);

COMMENT ON TABLE financial_overrides IS 'spine_v1: Audit trail when humans override Gandalf cost code inferences';
;
