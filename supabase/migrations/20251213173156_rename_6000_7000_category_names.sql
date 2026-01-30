
-- Migration: Rename 6000 and 7000 category codes
-- Updated per CTO directive 2025-12-13

UPDATE cost_codes SET cost_code_name = 'INTERIOR FINISHES' 
WHERE cost_code_number = '6000';

UPDATE cost_codes SET cost_code_name = 'SYSTEMS FINISHES' 
WHERE cost_code_number = '7000';
;
