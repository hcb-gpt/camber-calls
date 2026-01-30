
-- blood_v1: Vendor to cost code mapping (ontology layer)
-- Deterministic (trade→division) + probabilistic (keyword intersection)

CREATE TABLE vendor_cost_code_map (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  cost_code_id UUID NOT NULL REFERENCES cost_codes(id) ON DELETE CASCADE,
  mapping_type TEXT NOT NULL CHECK (mapping_type IN ('primary', 'secondary', 'inferred')),
  confidence DECIMAL(3,2) DEFAULT 1.00,
  keyword_overlap_count INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(contact_id, cost_code_id)
);

CREATE INDEX idx_vendor_cost_code_map_contact ON vendor_cost_code_map(contact_id);
CREATE INDEX idx_vendor_cost_code_map_cost_code ON vendor_cost_code_map(cost_code_id);
CREATE INDEX idx_vendor_cost_code_map_type ON vendor_cost_code_map(mapping_type);

COMMENT ON TABLE vendor_cost_code_map IS 'blood_v1: Links vendors (contacts) to their typical cost codes';
COMMENT ON COLUMN vendor_cost_code_map.mapping_type IS 'primary=deterministic trade match, secondary=alternate codes, inferred=keyword-derived';
COMMENT ON COLUMN vendor_cost_code_map.confidence IS '1.00 for deterministic, <1 for probabilistic inference';
;
