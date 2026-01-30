-- Drop unused indexes on contacts and interactions

-- contacts (358 rows) - gin indexes never used
DROP INDEX IF EXISTS idx_contacts_aliases_gin;
DROP INDEX IF EXISTS idx_contacts_company_aliases_gin;

-- interactions (474 rows) - candidate_projects index never used
DROP INDEX IF EXISTS idx_interactions_candidate_projects;

-- calls_raw zapier lineage indexes (never used)
DROP INDEX IF EXISTS idx_calls_raw_zapier_run_id;
DROP INDEX IF EXISTS idx_calls_raw_zapier_zap_id;

-- event_audit indexes (only 12 rows, indexes never used)
DROP INDEX IF EXISTS idx_event_audit_gate_status;
DROP INDEX IF EXISTS idx_event_audit_not_persisted;

-- vendor_cost_code_summary (materialized view)
DROP INDEX IF EXISTS idx_vendor_cost_code_summary_contact;;
