-- Table for A/B/C transcript comparison
-- Stores transcripts from multiple engines for the same call
-- Enables comparison of downstream Camber results

CREATE TABLE transcripts_comparison (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  interaction_id TEXT NOT NULL,
  
  -- Engine identification
  engine TEXT NOT NULL CHECK (engine IN ('beside', 'whisper', 'claude', 'assemblyai', 'deepgram')),
  model TEXT,  -- e.g., 'whisper-1', 'claude-sonnet-4-20250514'
  
  -- Transcript content
  transcript TEXT,
  transcript_compressed TEXT,  -- Claude compressed version if available
  
  -- Audio metadata
  audio_size_bytes INTEGER,
  duration_seconds NUMERIC,
  
  -- Cost/usage tracking
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_cents NUMERIC,  -- Estimated cost in cents
  
  -- Quality metrics (populated by evaluation)
  word_count INTEGER,
  has_speaker_labels BOOLEAN DEFAULT FALSE,
  speaker_count INTEGER,
  
  -- Downstream comparison (populated after pipeline run)
  claims_extracted INTEGER,
  entities_found INTEGER,
  pipeline_run_id UUID,  -- Link to pipeline execution
  
  -- Timing
  transcription_ms INTEGER,  -- How long transcription took
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- Ensure one transcript per engine per interaction
  UNIQUE(interaction_id, engine)
);

-- Indexes for common queries
CREATE INDEX idx_transcripts_comparison_interaction ON transcripts_comparison(interaction_id);
CREATE INDEX idx_transcripts_comparison_engine ON transcripts_comparison(engine);
CREATE INDEX idx_transcripts_comparison_created ON transcripts_comparison(created_at DESC);

-- Comments
COMMENT ON TABLE transcripts_comparison IS 'A/B/C comparison of transcripts from different engines (Beside, Whisper, Claude, etc.)';
COMMENT ON COLUMN transcripts_comparison.engine IS 'Transcription engine: beside, whisper, claude, assemblyai, deepgram';
COMMENT ON COLUMN transcripts_comparison.pipeline_run_id IS 'Links to pipeline execution for comparing downstream results';;
