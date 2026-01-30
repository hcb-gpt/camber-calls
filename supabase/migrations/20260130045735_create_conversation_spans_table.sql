-- conversation_spans: Segments of a call (initially 1:1 with interactions for trivial segmenter)
CREATE TABLE conversation_spans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id TEXT NOT NULL REFERENCES interactions(interaction_id),
  span_index INTEGER NOT NULL DEFAULT 0,
  
  -- Position markers (character-based for transcript alignment)
  char_start INTEGER,
  char_end INTEGER,
  line_start INTEGER,
  line_end INTEGER,
  
  -- Time markers (from Deepgram words array)
  time_start_sec NUMERIC(10,3),
  time_end_sec NUMERIC(10,3),
  
  -- Content
  transcript_segment TEXT,
  word_count INTEGER,
  
  -- Segmentation metadata
  segmenter_version TEXT NOT NULL DEFAULT 'trivial_v1',
  segment_reason TEXT,  -- 'full_call', 'gap_split', 'topic_shift', etc.
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(interaction_id, span_index)
);

-- Index for lookups
CREATE INDEX idx_conversation_spans_interaction ON conversation_spans(interaction_id);

COMMENT ON TABLE conversation_spans IS 'Segments of calls for fine-grained attribution. Trivial segmenter: 1 span = whole call.';;
