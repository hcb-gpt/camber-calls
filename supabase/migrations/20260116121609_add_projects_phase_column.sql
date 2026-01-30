ALTER TABLE projects 
ADD COLUMN IF NOT EXISTS phase text 
CHECK (phase IN ('pre_construction', 'active', 'punch_list', 'warranty', 'closed', 'on_hold'));

COMMENT ON COLUMN projects.phase IS 'Project lifecycle phase for filtering and routing';;
