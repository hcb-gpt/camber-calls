-- TYPE ALIGNMENT PLAN P4: Project Phase Population
-- Per STRATA-25 Type Alignment Plan v0.1

-- Infer phase from project status
UPDATE projects SET phase = 'active'
WHERE status IN ('active', 'Active', 'In Progress');

UPDATE projects SET phase = 'pre_construction'
WHERE status IN ('estimating', 'Pending') OR phase IS NULL AND status IS NULL;

UPDATE projects SET phase = 'closed'
WHERE status IN ('closed', 'Completed', 'inactive');

UPDATE projects SET phase = 'warranty'
WHERE status = 'warranty';

-- Catch any remaining NULLs
UPDATE projects SET phase = 'active'
WHERE phase IS NULL;;
