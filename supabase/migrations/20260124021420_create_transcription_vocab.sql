-- Create transcription vocabulary table for dynamic vocabulary priming
CREATE TABLE IF NOT EXISTS public.transcription_vocab (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term text NOT NULL UNIQUE,
  boost numeric(3,1) DEFAULT 1.0,
  category text CHECK (category IN ('person', 'project', 'location', 'trade', 'material', 'action')),
  source text CHECK (source IN ('static', 'project', 'contact', 'extraction', 'correction')),
  source_id uuid,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz,
  use_count int DEFAULT 0,
  false_positive_count int DEFAULT 0,
  active boolean DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_transcription_vocab_active
  ON public.transcription_vocab(active)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_transcription_vocab_category
  ON public.transcription_vocab(category);
;
