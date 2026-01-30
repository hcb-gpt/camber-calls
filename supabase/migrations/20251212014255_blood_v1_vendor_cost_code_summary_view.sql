
-- blood_v1: Materialized view for finance reporting
-- "Which vendors map to which cost codes?"

CREATE MATERIALIZED VIEW vendor_cost_code_summary AS
SELECT 
  c.id AS contact_id,
  c.name AS vendor_name,
  c.company,
  c.trade,
  cc.cost_code_number,
  cc.cost_code_name,
  cc.division,
  cc.phase_sequence,
  vcm.mapping_type,
  vcm.confidence
FROM contacts c
JOIN vendor_cost_code_map vcm ON c.id = vcm.contact_id
JOIN cost_codes cc ON vcm.cost_code_id = cc.id
ORDER BY c.trade, vcm.mapping_type, cc.phase_sequence;

CREATE INDEX idx_vcc_summary_trade ON vendor_cost_code_summary(trade);
CREATE INDEX idx_vcc_summary_cost_code ON vendor_cost_code_summary(cost_code_number);

COMMENT ON MATERIALIZED VIEW vendor_cost_code_summary IS 'blood_v1: Flattened vendor↔cost code mappings for reporting';
;
