-- Add interaction tracking for contact prioritization
ALTER TABLE contacts 
ADD COLUMN interaction_count integer DEFAULT 0,
ADD COLUMN last_interaction_at timestamptz;

COMMENT ON COLUMN contacts.interaction_count IS 'Total interaction count across all channels (calls, emails, messages)';
COMMENT ON COLUMN contacts.last_interaction_at IS 'Most recent interaction timestamp for recency sorting';

-- Index for efficient sorting by activity
CREATE INDEX idx_contacts_interaction_priority ON contacts (interaction_count DESC, last_interaction_at DESC NULLS LAST);;
