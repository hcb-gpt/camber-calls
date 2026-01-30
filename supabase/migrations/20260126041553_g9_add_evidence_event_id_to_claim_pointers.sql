-- G9: Add evidence_event_id FK to claim_pointers
-- Per invariant #3: downstream references use evidence_event_id as durable join key

ALTER TABLE claim_pointers 
ADD COLUMN evidence_event_id UUID REFERENCES evidence_events(evidence_event_id);

CREATE INDEX idx_claim_pointers_evidence_event_id ON claim_pointers(evidence_event_id);

COMMENT ON COLUMN claim_pointers.evidence_event_id IS 
'G9: Durable join key to evidence_events. Replaces source_id for canonical linkage.';;
