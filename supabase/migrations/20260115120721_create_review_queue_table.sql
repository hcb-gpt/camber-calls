-- Migration: Create review_queue as canonical destination for "refuse to guess"
-- Minimum viable: open/resolved record pointing at interaction and/or scheduler_item

CREATE TABLE IF NOT EXISTS review_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- What needs review
  interaction_id uuid REFERENCES interactions(id),
  scheduler_item_id uuid REFERENCES scheduler_items(id),
  
  -- Why it needs review
  reasons text[] NOT NULL,
  context_payload jsonb,  -- small blob for reviewer context
  
  -- Lifecycle
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by text,  -- user identifier
  resolution_action text,  -- 'confirmed', 'rejected', 'edited', 'dismissed'
  resolution_notes text,
  
  CONSTRAINT chk_review_queue_status CHECK (status IN ('pending', 'resolved', 'dismissed')),
  CONSTRAINT chk_review_queue_has_target CHECK (interaction_id IS NOT NULL OR scheduler_item_id IS NOT NULL)
);

-- Indexes for queue operations
CREATE INDEX IF NOT EXISTS idx_review_queue_status ON review_queue(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_review_queue_interaction ON review_queue(interaction_id);
CREATE INDEX IF NOT EXISTS idx_review_queue_scheduler_item ON review_queue(scheduler_item_id);
CREATE INDEX IF NOT EXISTS idx_review_queue_created ON review_queue(created_at DESC);

COMMENT ON TABLE review_queue IS 'Canonical sink for needs_review=true items. Single destination for "refuse to guess" pattern.';
COMMENT ON COLUMN review_queue.reasons IS 'Array of reason codes: low_confidence, unknown_project, cross_project, ambiguous_contact, etc.';
COMMENT ON COLUMN review_queue.resolution_action IS 'What the human did: confirmed, rejected, edited, dismissed';;
