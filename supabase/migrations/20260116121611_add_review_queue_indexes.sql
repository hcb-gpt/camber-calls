CREATE INDEX IF NOT EXISTS idx_review_queue_status ON review_queue(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_review_queue_created_at ON review_queue(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_review_queue_interaction_id ON review_queue(interaction_id);;
