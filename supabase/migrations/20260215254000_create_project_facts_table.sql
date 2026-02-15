-- Minimal time-synced world model foundation: project_facts
-- Stores project facts with explicit as_of_at (time-synced) + provenance pointers.

BEGIN;

CREATE TABLE IF NOT EXISTS public.project_facts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- Fact identity + value
  fact_key TEXT NOT NULL,
  fact_value JSONB NOT NULL,

  -- Time-synced semantics:
  -- - as_of_at: when this fact is true/effective in the world model
  -- - observed_at: when we observed/extracted it (may be >= as_of_at)
  as_of_at TIMESTAMPTZ NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Provenance (best-effort; at least one pointer unless manual)
  source_kind TEXT NOT NULL DEFAULT 'unknown',
  source_interaction_id TEXT,
  source_span_id UUID REFERENCES public.conversation_spans(id) ON DELETE SET NULL,
  source_span_attribution_id UUID REFERENCES public.span_attributions(id) ON DELETE SET NULL,
  source_journal_claim_row_id UUID REFERENCES public.journal_claims(id) ON DELETE SET NULL,
  source_char_start INTEGER,
  source_char_end INTEGER,
  source_quote TEXT,

  confidence NUMERIC,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT project_facts_fact_key_nonempty CHECK (btrim(fact_key) <> ''),
  CONSTRAINT project_facts_confidence_range CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  CONSTRAINT project_facts_provenance_present CHECK (
    source_kind = 'manual'
    OR source_interaction_id IS NOT NULL
    OR source_span_id IS NOT NULL
    OR source_span_attribution_id IS NOT NULL
    OR source_journal_claim_row_id IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_project_facts_project_key_asof
  ON public.project_facts(project_id, fact_key, as_of_at DESC);

CREATE INDEX IF NOT EXISTS idx_project_facts_project_asof
  ON public.project_facts(project_id, as_of_at DESC);

CREATE INDEX IF NOT EXISTS idx_project_facts_source_interaction_id
  ON public.project_facts(source_interaction_id)
  WHERE source_interaction_id IS NOT NULL;

COMMENT ON TABLE public.project_facts IS
  'Time-synced project facts (as_of_at) with provenance pointers for evidence packs.';

-- Helper: retrieve latest fact values as-of a given timestamp.
CREATE OR REPLACE FUNCTION public.project_facts_as_of(
  p_project_id UUID,
  p_as_of_at TIMESTAMPTZ
)
RETURNS TABLE (
  id UUID,
  project_id UUID,
  fact_key TEXT,
  fact_value JSONB,
  as_of_at TIMESTAMPTZ,
  observed_at TIMESTAMPTZ,
  source_kind TEXT,
  source_interaction_id TEXT,
  source_span_id UUID,
  source_span_attribution_id UUID,
  source_journal_claim_row_id UUID,
  source_char_start INTEGER,
  source_char_end INTEGER,
  source_quote TEXT,
  confidence NUMERIC,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT ON (pf.fact_key)
    pf.id,
    pf.project_id,
    pf.fact_key,
    pf.fact_value,
    pf.as_of_at,
    pf.observed_at,
    pf.source_kind,
    pf.source_interaction_id,
    pf.source_span_id,
    pf.source_span_attribution_id,
    pf.source_journal_claim_row_id,
    pf.source_char_start,
    pf.source_char_end,
    pf.source_quote,
    pf.confidence,
    pf.created_at
  FROM public.project_facts pf
  WHERE pf.project_id = p_project_id
    AND pf.as_of_at <= p_as_of_at
  ORDER BY
    pf.fact_key,
    pf.as_of_at DESC,
    pf.observed_at DESC,
    pf.created_at DESC,
    pf.id DESC;
$$;

GRANT EXECUTE ON FUNCTION public.project_facts_as_of(UUID, TIMESTAMPTZ) TO service_role;
REVOKE EXECUTE ON FUNCTION public.project_facts_as_of(UUID, TIMESTAMPTZ) FROM anon, authenticated;

COMMENT ON FUNCTION public.project_facts_as_of IS
  'Returns the latest value per fact_key for a project as-of p_as_of_at (time-synced world model).';

COMMIT;

