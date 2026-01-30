-- TYPE ALIGNMENT PLAN P1: Role Normalization - Execute
-- Per STRATA-25 Type Alignment Plan v0.1

-- Step 2: Normalize case variants to 'owner'
UPDATE contacts SET role = 'owner'
WHERE LOWER(role) IN ('owner', 'homeowner', 'client');

-- Step 3: Normalize project manager variants
UPDATE contacts SET role = 'project_manager'
WHERE LOWER(role) IN ('project manager', 'pm');

-- Step 4: Normalize sales variants
UPDATE contacts SET role = 'sales'
WHERE LOWER(role) IN ('sales', 'sales rep', 'account manager', 'sales consultant');

-- Step 5: Normalize office manager variants
UPDATE contacts SET role = 'office_manager'
WHERE LOWER(role) IN ('office manager', 'office admin');

-- Step 6: Normalize superintendent variants
UPDATE contacts SET role = 'superintendent'
WHERE LOWER(role) IN ('superintendent', 'super', 'site manager');

-- Step 7: Normalize inspector variants
UPDATE contacts SET role = 'inspector'
WHERE LOWER(role) IN ('building inspector', 'inspector', 'code inspector');

-- Step 8: Normalize subcontractor role (already has contact_type, role is redundant)
UPDATE contacts SET role = NULL
WHERE LOWER(role) = 'subcontractor';

-- Step 9: Move trade names from role to trade field
UPDATE contacts SET
  trade = COALESCE(trade, role),
  role = NULL
WHERE LOWER(role) IN (
  'electrician', 'painter', 'plumber', 'carpenter', 'framer', 
  'siding', 'drywall', 'hvac', 'roofer', 'installer',
  'soil scientist', 'engineer (underground service)'
);

-- Step 10: Normalize architect/engineer to professional roles
UPDATE contacts SET role = 'architect'
WHERE LOWER(role) = 'architect';

UPDATE contacts SET role = 'engineer'
WHERE LOWER(role) LIKE '%engineer%' AND role IS NOT NULL;

-- Step 11: Normalize scheduling to office_manager
UPDATE contacts SET role = 'office_manager'
WHERE LOWER(role) IN ('scheduling', 'showroom consultant');

-- Step 12: Normalize attorney to 'professional' (will add to enum if needed)
UPDATE contacts SET role = 'professional'
WHERE LOWER(role) IN ('attorney', 'agent');

-- Step 13: Clean up 'other' and 'personal' to NULL (these are contact_types, not roles)
UPDATE contacts SET role = NULL
WHERE LOWER(role) IN ('other', 'personal');;
