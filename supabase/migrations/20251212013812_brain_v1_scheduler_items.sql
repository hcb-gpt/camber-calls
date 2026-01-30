
-- brain_v1: Scheduler items table
-- Derived tasks/events from interactions

CREATE TABLE scheduler_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id UUID NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL CHECK (item_type IN ('task', 'event', 'deadline', 'follow_up', 'other')),
  title TEXT NOT NULL,
  description TEXT,
  time_hint TEXT,  -- raw hint from AI e.g., "next Tuesday", "Friday at 3pm"
  start_at_utc TIMESTAMPTZ,
  due_at_utc TIMESTAMPTZ,
  assignee TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
  financial_json JSONB DEFAULT NULL,  -- blood_v1: same structure as interactions.financial_json
  scheduler_schema_version INTEGER DEFAULT 2,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_scheduler_items_interaction ON scheduler_items(interaction_id);
CREATE INDEX idx_scheduler_items_type ON scheduler_items(item_type);
CREATE INDEX idx_scheduler_items_due ON scheduler_items(due_at_utc);
CREATE INDEX idx_scheduler_items_status ON scheduler_items(status);

COMMENT ON TABLE scheduler_items IS 'brain_v1: Schedulable tasks/events derived from interactions';
COMMENT ON COLUMN scheduler_items.financial_json IS 'blood_v1: Denormalized financial inference for this item';
COMMENT ON COLUMN scheduler_items.time_hint IS 'Raw time reference from transcript, parsed into start_at_utc/due_at_utc';
;
