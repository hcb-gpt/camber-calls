-- ============================================================
-- VENDOR REGISTRY REFACTOR - DDL
-- Version: 2025-12-15
-- Idempotent: safe to re-run
-- ============================================================

-- 1. vendors_v: Clean vendor interface for blood_v1
CREATE OR REPLACE VIEW vendors_v AS
SELECT 
  c.id as vendor_id,
  c.name as vendor_name,
  c.company as company_name,
  c.trade as trade_classification,
  c.phone,
  c.email,
  c.aliases,
  c.company_aliases,
  c.core_business_keywords as vendor_keywords,
  COALESCE(
    (SELECT array_agg(DISTINCT vccm.cost_code ORDER BY vccm.cost_code)
     FROM vendor_cost_code_map vccm 
     WHERE vccm.contact_id = c.id AND vccm.mapping_type = 'primary'),
    ARRAY[]::char(4)[]
  ) as primary_cost_codes,
  COALESCE(
    (SELECT array_agg(DISTINCT vccm.cost_code ORDER BY vccm.cost_code)
     FROM vendor_cost_code_map vccm 
     WHERE vccm.contact_id = c.id),
    ARRAY[]::char(4)[]
  ) as all_cost_codes
FROM contacts c
WHERE c.contact_type IN ('vendor', 'subcontractor', 'site_supervisor')
  AND c.company IS NOT NULL;

-- 2. Validate core_business_keywords as JSON array
CREATE OR REPLACE FUNCTION validate_keywords_jsonb()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.core_business_keywords IS NOT NULL 
     AND jsonb_typeof(NEW.core_business_keywords) != 'array' THEN
    RAISE EXCEPTION 'core_business_keywords must be a JSON array, got: %', jsonb_typeof(NEW.core_business_keywords);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_keywords ON contacts;
CREATE TRIGGER trg_validate_keywords
BEFORE INSERT OR UPDATE ON contacts
FOR EACH ROW EXECUTE FUNCTION validate_keywords_jsonb();

-- 3. Vendor/subcontractor must have trade OR company
-- Drop if exists first (can't use IF NOT EXISTS for CHECK constraints)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'chk_vendor_has_trade_or_company' 
    AND conrelid = 'contacts'::regclass
  ) THEN
    ALTER TABLE contacts ADD CONSTRAINT chk_vendor_has_trade_or_company
    CHECK (
      contact_type NOT IN ('vendor', 'subcontractor') 
      OR trade IS NOT NULL 
      OR company IS NOT NULL
    );
  END IF;
END $$;

-- 4. QA view: contacts with email/phone in notes
CREATE OR REPLACE VIEW contacts_notes_qa AS
SELECT id, name, contact_type, notes
FROM contacts
WHERE notes IS NOT NULL
  AND (
    notes ~ '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
    OR notes ~ '\(\d{3}\)\s*\d{3}[-.]\d{4}'
    OR notes ~ '\d{3}[-.]\d{3}[-.]\d{4}'
  );

-- 5. QA view: internal contacts with non-Heartwood company
CREATE OR REPLACE VIEW contacts_internal_company_qa AS
SELECT id, name, company, contact_type
FROM contacts
WHERE contact_type = 'internal'
  AND company IS NOT NULL
  AND company NOT ILIKE '%heartwood%';

-- 6. Inference support view: resolved_vendor_for_contact
CREATE OR REPLACE VIEW resolved_vendor_for_contact AS
SELECT 
  c.id as contact_id,
  c.phone,
  c.name as contact_name,
  c.company as vendor_name,
  c.trade,
  c.aliases,
  c.company_aliases,
  array_agg(DISTINCT cct.code ORDER BY cct.code) FILTER (WHERE cct.code IS NOT NULL) as cost_codes,
  array_agg(DISTINCT cct.division) FILTER (WHERE cct.division IS NOT NULL) as divisions
FROM contacts c
LEFT JOIN vendor_cost_code_map vccm ON vccm.contact_id = c.id
LEFT JOIN cost_code_taxonomy cct ON cct.code = vccm.cost_code
WHERE c.contact_type IN ('vendor', 'subcontractor', 'site_supervisor')
GROUP BY c.id, c.phone, c.name, c.company, c.trade, c.aliases, c.company_aliases;;
