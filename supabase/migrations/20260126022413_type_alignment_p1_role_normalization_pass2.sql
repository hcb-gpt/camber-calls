-- TYPE ALIGNMENT PLAN P1: Role Normalization - Pass 2
-- Additional normalizations discovered from data

-- Move more trade names to trade field
UPDATE contacts SET
  trade = COALESCE(trade, role),
  role = NULL
WHERE LOWER(role) IN (
  'brick mason', 'tile contractor', 'trim carpenter', 'lead carpenter',
  'equipment operator', 'gas hookup', 'cleaning', 'millwork', 
  'stone supplier', 'landscaper', 'salvage', 'fence builder',
  'hardscape', 'gutters', 'tile', 'concrete sub', 'grading',
  'cabinets', 'fabricator', 'hvac tech', 'technician'
);

-- Normalize executive/manager titles to appropriate roles
UPDATE contacts SET role = 'executive'
WHERE LOWER(role) IN (
  'president', 'founder & ceo', 'chief operating officer', 
  'vice president sales', 'managing partner', 'principal'
);

-- Normalize sales-related titles
UPDATE contacts SET role = 'sales'
WHERE LOWER(role) IN (
  'business development rep', 'account executive', 'senior broker',
  'showroom designer & sales', 'account manager assistant',
  'outside sales coordinator', 'showroom manager', 'senior showroom consultant',
  'regional manager architectural sales', 'midwest representative',
  'atlanta window market specialist', 'design consultant'
);

-- Normalize manager titles to office_manager
UPDATE contacts SET role = 'office_manager'
WHERE LOWER(role) IN (
  'branch manager', 'manager', 'market collection manager', 
  'market collections manager', 'setup manager', 'department coordinator',
  'survey department manager', 'customer migration manager', 'farm manager'
);

-- Normalize architect variants
UPDATE contacts SET role = 'architect'
WHERE LOWER(role) IN ('principal architect', 'project architect', 'ewp designer', 'ewp design manager');

-- Normalize project manager variants
UPDATE contacts SET role = 'project_manager'
WHERE LOWER(role) IN ('project rep', 'senior project manager');

-- Normalize inspector/planning roles
UPDATE contacts SET role = 'inspector'
WHERE LOWER(role) IN ('plan review', 'planning', 'director, building & planning');

-- Normalize professional services
UPDATE contacts SET role = 'professional'
WHERE LOWER(role) IN (
  'consultant', 'mortgage advisor', 'loan officer', 'developer',
  'photographer', 'bookkeeper', 'hr', 'technical support', 'clerk'
);

-- Normalize general contractor
UPDATE contacts SET role = 'general_contractor'
WHERE LOWER(role) IN ('general contractor', 'supervisor');

-- Special cases
UPDATE contacts SET role = 'owner'
WHERE LOWER(role) IN ('partner', 'tenant', 'neighbor');

UPDATE contacts SET role = NULL
WHERE LOWER(role) = 'company';;
