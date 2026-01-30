
-- ================================================
-- MEASUREMENT VIEWS FOR AI-FORWARD GATE
-- ================================================

-- Auto-pass rate by day
CREATE OR REPLACE VIEW v_event_audit_pass_rate AS
SELECT 
  date_trunc('day', received_at_utc) as day,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE gate_status = 'pass') as auto_pass,
  COUNT(*) FILTER (WHERE gate_status = 'needs_human') as needs_human,
  COUNT(*) FILTER (WHERE gate_status = 'fail') as failed,
  ROUND(100.0 * COUNT(*) FILTER (WHERE gate_status = 'pass') / NULLIF(COUNT(*), 0), 1) as auto_pass_pct,
  ROUND(100.0 * COUNT(*) FILTER (WHERE gate_status = 'needs_human') / NULLIF(COUNT(*), 0), 1) as needs_human_pct
FROM event_audit
GROUP BY 1
ORDER BY 1 DESC;

-- Lineage coverage by day (new records)
CREATE OR REPLACE VIEW v_lineage_coverage AS
SELECT 
  date_trunc('day', ingested_at_utc) as day,
  COUNT(*) as total,
  COUNT(zap_id) as has_zap_id,
  COUNT(zap_step_id) as has_zap_step_id,
  ROUND(100.0 * COUNT(zap_id) / NULLIF(COUNT(*), 0), 1) as zap_id_pct,
  ROUND(100.0 * COUNT(zap_step_id) / NULLIF(COUNT(*), 0), 1) as zap_step_id_pct
FROM calls_raw
WHERE ingested_at_utc > now() - interval '30 days'
GROUP BY 1
ORDER BY 1 DESC;

-- Human queue (needs attention)
CREATE OR REPLACE VIEW v_event_audit_human_queue AS
SELECT 
  id,
  interaction_id,
  received_at_utc,
  gate_reasons,
  source_run_id,
  source_zap_id
FROM event_audit
WHERE gate_status = 'needs_human'
  AND NOT persisted_to_calls_raw
ORDER BY received_at_utc DESC;

-- Gate reason breakdown
CREATE OR REPLACE VIEW v_event_audit_reason_breakdown AS
SELECT 
  reason,
  COUNT(*) as occurrences,
  COUNT(*) FILTER (WHERE received_at_utc > now() - interval '24 hours') as last_24h
FROM event_audit,
LATERAL jsonb_array_elements_text(gate_reasons) as reason
GROUP BY reason
ORDER BY occurrences DESC;
;
