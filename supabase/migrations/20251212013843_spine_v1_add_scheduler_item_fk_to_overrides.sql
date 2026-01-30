
-- spine_v1: Now that scheduler_items exists, add proper FK

ALTER TABLE financial_overrides
ADD CONSTRAINT fk_financial_overrides_scheduler_item 
FOREIGN KEY (scheduler_item_id) REFERENCES scheduler_items(id) ON DELETE CASCADE;

CREATE INDEX idx_financial_overrides_scheduler_item ON financial_overrides(scheduler_item_id);
;
