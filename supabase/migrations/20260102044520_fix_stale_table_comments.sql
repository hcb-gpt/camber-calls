
-- Fix misleading idempotency_keys comment
COMMENT ON TABLE idempotency_keys IS 
'Webhook idempotency tracking. Key = interaction_id (e.g., cll_*) directly.';

-- Update legacy terminology in other comments
COMMENT ON TABLE contact_relationships IS 
'Contact-to-contact relationships (spouse, employee, business partner, etc.)';

COMMENT ON TABLE entity_relationship_candidates IS 
'Candidate relationships extracted from corpus, pending human approval';

COMMENT ON TABLE financial_overrides IS 
'Audit trail for cost code override decisions';

COMMENT ON TABLE inference_config IS 
'Tunable thresholds for Sensemaking inference';

COMMENT ON TABLE interactions IS 
'Event spine: one row per interaction (call, SMS, email)';

COMMENT ON TABLE scheduler_items IS 
'Extracted tasks/events from interactions';

COMMENT ON TABLE vendor_cost_code_map IS 
'Vendor-to-cost-code mappings for financial inference';
;
