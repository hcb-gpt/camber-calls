
-- Document the financial_json contract as a comment on the interactions table
COMMENT ON COLUMN interactions.financial_json IS 
'blood_v1 schema v2 contract:
{
  "vendor_id": "uuid | null",
  "vendor_name": "string | null", 
  "probable_cost_codes": [
    {
      "cost_code_id": "uuid",
      "cost_code_number": "string",
      "cost_code_name": "string",
      "confidence": "decimal 0.00-1.00",
      "mapping_type": "primary | secondary | inferred",
      "reasoning": "string"
    }
  ],
  "inference_status": "auto_assigned | flagged_for_review | no_inference | pending",
  "inferred_at_utc": "timestamp",
  "schema_version": 2
}';

COMMENT ON COLUMN scheduler_items.financial_json IS 
'blood_v1 schema v2 contract - inherits from parent interaction or item-specific override:
{
  "vendor_id": "uuid | null",
  "vendor_name": "string | null",
  "probable_cost_codes": [
    {
      "cost_code_id": "uuid",
      "cost_code_number": "string",  
      "cost_code_name": "string",
      "confidence": "decimal 0.00-1.00",
      "mapping_type": "primary | secondary | inferred",
      "reasoning": "string"
    }
  ],
  "inference_status": "auto_assigned | flagged_for_review | no_inference | pending | inherited",
  "inherited_from_interaction": "boolean",
  "inferred_at_utc": "timestamp",
  "schema_version": 2
}';
;
