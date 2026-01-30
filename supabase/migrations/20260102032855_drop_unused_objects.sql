
-- Drop unused tables
DROP TABLE IF EXISTS call_commitments;
DROP TABLE IF EXISTS digest_runs;

-- Drop unused views
DROP VIEW IF EXISTS contacts_internal_company_qa;
DROP VIEW IF EXISTS v_financial_overrides_audit;
DROP VIEW IF EXISTS v_financial_inference_coverage;

-- Drop one-time migration function
DROP FUNCTION IF EXISTS backfill_scheduler_items;
;
