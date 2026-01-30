
-- Required for journal_extract v1.4 upsert(onConflict='call_id,item_type,item_id')

-- remove duplicates (keep earliest) for non-null item_id
DELETE FROM journal_review_queue a
USING journal_review_queue b
WHERE a.call_id = b.call_id
  AND a.item_type = b.item_type
  AND a.item_id = b.item_id
  AND a.item_id IS NOT NULL
  AND a.ctid > b.ctid;

CREATE UNIQUE INDEX IF NOT EXISTS journal_review_queue_call_item_uniq
  ON journal_review_queue (call_id, item_type, item_id);
;
