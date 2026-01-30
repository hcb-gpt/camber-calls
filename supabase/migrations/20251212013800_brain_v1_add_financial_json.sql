
-- brain_v1 schema_version 2: Add financial_json to interactions
-- Denormalized financial inference results

ALTER TABLE interactions 
ADD COLUMN financial_json JSONB DEFAULT NULL;

COMMENT ON COLUMN interactions.financial_json IS 'blood_v1: Denormalized financial inference {vendor_id, probable_cost_codes[], confidence, reasoning}';

-- Update schema version marker
-- Existing rows remain schema_version=1 (or 0), new rows with financial_json populated = v2
;
