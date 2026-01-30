-- Ground truth labels for attribution accuracy tracking
-- Owner: DATA-22 (labeler), STRATA23 (approved schema)
-- Purpose: Gate D wrong-project promotion metric, A/B testing

CREATE TABLE ground_truth_labels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id TEXT NOT NULL,
  project_attribution TEXT NOT NULL,
  confidence TEXT CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW')),
  labeler TEXT DEFAULT 'DATA-22',
  label_date TIMESTAMPTZ DEFAULT now(),
  notes TEXT,
  batch_id TEXT,
  UNIQUE (call_id)
);

-- Index for metric queries
CREATE INDEX idx_ground_truth_labels_confidence ON ground_truth_labels(confidence);
CREATE INDEX idx_ground_truth_labels_batch_id ON ground_truth_labels(batch_id);

COMMENT ON TABLE ground_truth_labels IS 'Human-labeled ground truth for call attribution accuracy measurement';
COMMENT ON COLUMN ground_truth_labels.call_id IS 'References interactions.id (cll_* format)';
COMMENT ON COLUMN ground_truth_labels.project_attribution IS 'Human-determined correct project name';
COMMENT ON COLUMN ground_truth_labels.confidence IS 'Labeler confidence: HIGH (explicit mention), MEDIUM (inferred), LOW (ambiguous)';;
