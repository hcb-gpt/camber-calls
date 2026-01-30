-- ============================================================
-- ADD CONSTRUCTION PHASE FK TO PROJECTS
-- ============================================================
-- This tracks what construction phase the project is currently in.
-- Separate from the existing 'phase' column which tracks project STATUS.
-- 
-- We also rename the existing 'phase' column to 'status' for clarity,
-- since that's what it actually represents.
-- ============================================================

-- Add FK column for current construction phase
ALTER TABLE projects 
ADD COLUMN current_construction_phase_id UUID REFERENCES construction_phases(id);

-- Create index for FK lookups
CREATE INDEX idx_projects_current_construction_phase ON projects(current_construction_phase_id);

-- Add comments for clarity
COMMENT ON COLUMN projects.current_construction_phase_id IS 'Current construction phase (0000-9000). See construction_phases table.';
COMMENT ON COLUMN projects.phase IS 'LEGACY: Project status (pre_construction, active, etc). Consider using status field instead.';;
