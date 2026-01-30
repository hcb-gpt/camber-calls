-- Migration: Add first-class attribution columns to scheduler_items
-- Moves attribution_status out of JSON payload into queryable columns
-- Enables: resolved rate, needs-review rate, trend tracking, SQL-driven review queue

ALTER TABLE scheduler_items
  ADD COLUMN IF NOT EXISTS project_id uuid REFERENCES projects(id),
  ADD COLUMN IF NOT EXISTS attribution_status text DEFAULT 'unknown',
  ADD COLUMN IF NOT EXISTS attribution_confidence numeric(3,2),
  ADD COLUMN IF NOT EXISTS needs_review boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS evidence_quote text,
  ADD COLUMN IF NOT EXISTS evidence_locator text;

-- Add check constraint for valid attribution statuses
ALTER TABLE scheduler_items
  ADD CONSTRAINT chk_attribution_status 
  CHECK (attribution_status IN ('resolved', 'needs_clarification', 'cross_project', 'quarantined', 'unknown'));

-- Indexes for metrics and review queue
CREATE INDEX IF NOT EXISTS idx_scheduler_items_project_id ON scheduler_items(project_id);
CREATE INDEX IF NOT EXISTS idx_scheduler_items_attribution_status ON scheduler_items(attribution_status);
CREATE INDEX IF NOT EXISTS idx_scheduler_items_needs_review ON scheduler_items(needs_review) WHERE needs_review = true;

COMMENT ON COLUMN scheduler_items.attribution_status IS 'First-class status: resolved|needs_clarification|cross_project|quarantined|unknown';
COMMENT ON COLUMN scheduler_items.attribution_confidence IS 'Router confidence for this item 0.00-1.00';;
