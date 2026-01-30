
-- Migration: Cost Code 0000/0010/0020 Taxonomy Revision v2
-- From: Strat memo dated 2025-12-11
-- Implements: Category designation, field management split, jobsite support addition

-- Step 1: Update 0000 to be a category (not assignable) with proper overhead keywords
UPDATE cost_codes
SET 
  cost_code_name = 'OVERHEAD (CATEGORY)',
  cost_code_keywords = jsonb_build_array(
    'bookkeeping',
    'accounting',
    'office admin',
    'technology',
    'software',
    'subscriptions',
    'general corporate overhead',
    'company overhead',
    'indirect costs'
  )
WHERE cost_code_number = '0000';

-- Step 2: Update 0010 to be FIELD MANAGEMENT / SUPERVISION with job-specific management keywords
UPDATE cost_codes
SET 
  cost_code_name = 'Field Management / Supervision',
  cost_code_keywords = jsonb_build_array(
    'superintendent',
    'site supervision',
    'project manager',
    'PM',
    'field management',
    'coordination',
    'scheduling',
    'site management',
    'jobsite meetings',
    'management time',
    'daily reports',
    'project coordination'
  )
WHERE cost_code_number = '0010';

-- Step 3: Create 0020 as JOBSITE SUPPORT / GENERAL CONDITIONS LABOR
INSERT INTO cost_codes (
  cost_code_number,
  cost_code_name,
  division,
  phase_sequence,
  cost_code_keywords
)
VALUES (
  '0020',
  'Jobsite Support / General Conditions Labor',
  'OVERHEAD',
  2,
  jsonb_build_array(
    'cleanup',
    'trash',
    'haul',
    'haul-off',
    'protect',
    'protection',
    'ram board',
    'plastic',
    'cover',
    'covering',
    'sweep',
    'stabilize',
    'staging',
    'unload',
    'move materials',
    'site tidy',
    'jobsite protection',
    'temp stabilization',
    'material handling',
    'PPE',
    'small tools',
    'field crew support'
  )
)
ON CONFLICT (cost_code_number) DO UPDATE
SET 
  cost_code_name = EXCLUDED.cost_code_name,
  cost_code_keywords = EXCLUDED.cost_code_keywords,
  updated_at = now();

-- Step 4: Add comment explaining taxonomy rules
COMMENT ON TABLE cost_codes IS 'blood_v1: Cost code taxonomy with keywords for inference matching

Taxonomy rules:
- Categories (NOT assignable): codes ending in 000 (e.g., 0000, 1000, 2000)
- Reserved subcategories (NOT assignable yet): codes ending in 00 but not 000 (e.g., 0100, 5200)
- Assignable cost codes: all other 4-digit values (e.g., 0010, 0020, 5030, 7020)';
;
