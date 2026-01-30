-- G9 Migration: Create evidence_events table
-- Per STRAT22_EMERITUS spec (2026-01-26_0401Z)
-- Modality-agnostic, write-once evidence layer

CREATE TABLE evidence_events (
  -- Primary key
  evidence_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Source identification
  source_type TEXT NOT NULL CHECK (source_type IN ('call', 'sms', 'photo', 'email', 'buildertrend', 'manual')),
  source_id TEXT NOT NULL,  -- Original ID (call_id, message_id, etc.)
  
  -- Payload reference (WRITE-ONCE after set)
  payload_ref TEXT,  -- URI/path to transcript/blob
  payload_hash TEXT, -- Content hash for integrity
  
  -- Transcript variant tracking
  transcript_variant TEXT CHECK (transcript_variant IN ('keywords_off', 'keywords_on', 'baseline', NULL)),
  
  -- Timestamps
  occurred_at TIMESTAMPTZ,  -- When the event happened
  ingested_at TIMESTAMPTZ DEFAULT NOW(),  -- When we captured it
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Law stamps (must be non-NULL for valid runs)
  canon_pack_version TEXT,
  promotion_policy_version TEXT,
  norm_version TEXT,
  segmentation_version TEXT,
  
  -- Metadata
  metadata JSONB,
  
  -- Prevent duplicate evidence for same source
  UNIQUE (source_type, source_id, transcript_variant)
);

-- Indexes
CREATE INDEX idx_evidence_events_source_id ON evidence_events(source_id);
CREATE INDEX idx_evidence_events_source_type ON evidence_events(source_type);
CREATE INDEX idx_evidence_events_ingested_at ON evidence_events(ingested_at);

COMMENT ON TABLE evidence_events IS 
'G9: Modality-agnostic evidence layer. Calls, SMS, photos, BT updates all become evidence_events. payload_ref is WRITE-ONCE.';
COMMENT ON COLUMN evidence_events.payload_ref IS 'WRITE-ONCE: Cannot be mutated once set. See trigger trg_payload_ref_write_once.';;
