
-- Fix orphaned review_queue entries by matching claim_text + run_id
-- The bug: review_queue.item_id was set to a different UUID than journal_claims.id
-- This migration updates item_id to point to the correct claim

UPDATE journal_review_queue jrq
SET item_id = jc.id
FROM journal_claims jc
WHERE jc.run_id = jrq.run_id
  AND jc.claim_text = jrq.data->>'claim_text'
  AND NOT EXISTS (SELECT 1 FROM journal_claims jc2 WHERE jc2.id = jrq.item_id);
;
