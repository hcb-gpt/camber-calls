
-- spine_v1: Diagnostic view for blood_v1 inference coverage
CREATE OR REPLACE VIEW v_financial_inference_coverage AS
SELECT
  i.channel,
  COUNT(*) as total_interactions,
  COUNT(i.financial_json) as with_financial_json,
  COUNT(*) FILTER (WHERE i.financial_json->>'inference_status' = 'auto_assigned') as auto_assigned,
  COUNT(*) FILTER (WHERE i.financial_json->>'inference_status' = 'flagged_for_review') as flagged_for_review,
  COUNT(*) FILTER (WHERE i.financial_json->>'inference_status' = 'no_inference') as no_inference,
  COUNT(*) FILTER (WHERE i.financial_json IS NULL) as pending_inference,
  ROUND(100.0 * COUNT(i.financial_json) / NULLIF(COUNT(*), 0), 1) as coverage_pct
FROM interactions i
GROUP BY i.channel;

-- spine_v1: View for override audit trail
CREATE OR REPLACE VIEW v_financial_overrides_audit AS
SELECT
  fo.id as override_id,
  i.interaction_id,
  i.channel,
  i.contact_name,
  i.event_at_local,
  cc_orig.cost_code_number as original_code,
  cc_orig.cost_code_name as original_name,
  fo.original_confidence,
  cc_new.cost_code_number as override_code,
  cc_new.cost_code_name as override_name,
  fo.override_reason,
  fo.overridden_by,
  fo.created_at as overridden_at
FROM financial_overrides fo
LEFT JOIN interactions i ON fo.interaction_id = i.id
LEFT JOIN cost_codes cc_orig ON fo.original_cost_code_id = cc_orig.id
LEFT JOIN cost_codes cc_new ON fo.override_cost_code_id = cc_new.id
ORDER BY fo.created_at DESC;

-- spine_v1: View for vendor inference summary
CREATE OR REPLACE VIEW v_vendor_inference_summary AS
SELECT
  c.name as vendor_name,
  c.trade,
  COUNT(DISTINCT vcc.cost_code_id) as mapped_cost_codes,
  STRING_AGG(DISTINCT cc.cost_code_number, ', ' ORDER BY cc.cost_code_number) as cost_codes,
  CASE WHEN c.id = ANY(
    (SELECT jsonb_array_elements_text(config_value)::uuid FROM inference_config WHERE config_key = 'p0_vendor_ids')
  ) THEN 'P0' ELSE 'P1' END as priority_tier
FROM contacts c
LEFT JOIN vendor_cost_code_map vcc ON c.id = vcc.contact_id
LEFT JOIN cost_codes cc ON vcc.cost_code_id = cc.id
WHERE c.contact_type = 'vendor'
GROUP BY c.id, c.name, c.trade
ORDER BY c.trade, c.name;
;
