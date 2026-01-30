-- Review queue idempotency: unique (item_id, reason) for claim items
-- Allows same claim to have multiple different reasons, but prevents duplicate reasons
CREATE UNIQUE INDEX IF NOT EXISTS journal_review_queue_claim_reason_ux
  ON public.journal_review_queue (item_id, reason)
  WHERE item_type = 'claim';;
