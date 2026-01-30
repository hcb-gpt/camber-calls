-- AI Router columns for span_attributions
-- Migration: add_ai_router_columns

-- AI decision columns
ALTER TABLE span_attributions
  ADD COLUMN IF NOT EXISTS decision text CHECK (decision IN ('assign', 'review', 'none')),
  ADD COLUMN IF NOT EXISTS reasoning text,
  ADD COLUMN IF NOT EXISTS anchors jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS suggested_aliases jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS prompt_version text,
  ADD COLUMN IF NOT EXISTS model_id text,
  ADD COLUMN IF NOT EXISTS raw_response jsonb,
  ADD COLUMN IF NOT EXISTS tokens_used integer,
  ADD COLUMN IF NOT EXISTS inference_ms integer;

-- Model output confidence
ALTER TABLE span_attributions
  ADD COLUMN IF NOT EXISTS confidence numeric CHECK (confidence >= 0 AND confidence <= 1);

-- SPAN-LEVEL lock and application tracking
ALTER TABLE span_attributions
  ADD COLUMN IF NOT EXISTS attribution_lock text CHECK (attribution_lock IN ('human', 'ai')),
  ADD COLUMN IF NOT EXISTS applied_project_id uuid,
  ADD COLUMN IF NOT EXISTS applied_at_utc timestamptz,
  ADD COLUMN IF NOT EXISTS needs_review boolean DEFAULT false;

-- IDEMPOTENCY: Prevent duplicate decisions on reruns
-- Note: model_id + prompt_version will be NOT NULL in code, index works on all rows
CREATE UNIQUE INDEX IF NOT EXISTS idx_span_attributions_idempotent
  ON span_attributions(span_id, model_id, prompt_version)
  WHERE model_id IS NOT NULL AND prompt_version IS NOT NULL;

-- Create eval_hard_spans table for span-level evaluation
CREATE TABLE IF NOT EXISTS eval_hard_spans (
  span_id uuid PRIMARY KEY REFERENCES conversation_spans(id),
  expected_project_id uuid REFERENCES projects(id),
  expected_project_name text,
  difficulty_reason text,
  labeler text,
  labeled_at timestamptz DEFAULT now()
);

-- Create call-level rollup view (optional convenience, spans are truth)
CREATE OR REPLACE VIEW v_call_primary_project AS
SELECT DISTINCT ON (cs.interaction_id)
  cs.interaction_id,
  sa.applied_project_id as project_id,
  sa.confidence
FROM conversation_spans cs
JOIN span_attributions sa ON sa.span_id = cs.id
WHERE sa.applied_project_id IS NOT NULL
ORDER BY cs.interaction_id, sa.confidence DESC NULLS LAST;;
