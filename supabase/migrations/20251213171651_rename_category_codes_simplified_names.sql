
-- Migration: Rename category codes to simplified names
-- Updated per CTO directive 2025-12-13

UPDATE cost_codes SET cost_code_name = 'OVERHEAD' 
WHERE cost_code_number = '0000';

UPDATE cost_codes SET cost_code_name = 'PRE-CONSTRUCTION' 
WHERE cost_code_number = '1000';

UPDATE cost_codes SET cost_code_name = 'SITE-WORK & FOUNDATION' 
WHERE cost_code_number = '2000';

UPDATE cost_codes SET cost_code_name = 'FRAMING' 
WHERE cost_code_number = '3000';

UPDATE cost_codes SET cost_code_name = 'DRY-IN' 
WHERE cost_code_number = '4000';

UPDATE cost_codes SET cost_code_name = 'ROUGH-IN' 
WHERE cost_code_number = '5000';

UPDATE cost_codes SET cost_code_name = 'INTERIOR ENCLOSURE' 
WHERE cost_code_number = '6000';

UPDATE cost_codes SET cost_code_name = 'INTERIOR FINISHES' 
WHERE cost_code_number = '7000';

UPDATE cost_codes SET cost_code_name = 'EXTERIOR FINISHES' 
WHERE cost_code_number = '8000';

-- 9000 stays the same: CLOSEOUT, FEES & FINANCIALS
;
