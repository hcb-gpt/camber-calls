-- ============================================================================
-- MIGRATION: Add attribution confidence tracking to journal_claims
-- PURPOSE: Break the feedback loop in journal-extract → context-assembly → ai-router
-- DATE: 2026-02-15
-- AUTHOR: DATA-1
-- ============================================================================
--
-- THE FEEDBACK LOOP BUG:
--
-- 1. ai-router attributes a span with decision='review' (uncertain, confidence
--    0.50-0.74) and writes to span_attributions with project_id set but
--    applied_project_id = NULL (because it's not confident enough to auto-assign).
--
-- 2. journal-extract reads span_attributions and uses:
--      const project_id = attribution?.applied_project_id || attribution?.project_id || null;
--    This falls through to the UNCERTAIN project_id (the one the router wasn't
--    confident about), treating it as if it were confirmed.
--
-- 3. journal-extract creates claims with that uncertain project_id, storing them
--    in journal_claims with NO record of how uncertain the attribution was.
--
-- 4. context-assembly later surfaces those claims as "journal context" (the
--    project_journal field in the context_package) for future ai-router runs
--    on calls involving the same candidate projects.
--
-- 5. Future ai-router sees claims that appear to confirm the uncertain project,
--    reinforcing the error. The router has no way to know these claims were born
--    from a "review" decision — they look identical to claims from high-confidence
--    "assign" attributions.
--
-- 6. Result: 2,691 claims (82% of all active claims) carry questionable project
--    attribution, and 2,857 downstream claims have been influenced by uncertain
--    journal context feeding back through the loop.
--
-- THIS FIX (Part A):
-- Add two columns to journal_claims that propagate the attribution's confidence
-- metadata from span_attributions at claim creation time. This enables
-- context-assembly (Fix B) to filter claims by confidence tier before surfacing
-- them as journal context, breaking the loop.
-- ============================================================================

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 1: ADD COLUMNS
-- ──────────────────────────────────────────────────────────────────────────────

-- attribution_decision: the ai-router's decision when the span was attributed.
-- Values: 'assign' (confident, auto-applied), 'review' (uncertain, needs human
-- review), 'none' (no match found). Propagated from span_attributions.decision
-- at claim creation time.
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS attribution_decision TEXT
  CHECK (attribution_decision IN ('assign', 'review', 'none'));

COMMENT ON COLUMN journal_claims.attribution_decision IS
  'AI-router decision at claim creation time (from span_attributions.decision). '
  'Used by context-assembly to filter uncertain claims out of journal context, '
  'breaking the feedback loop where review-tier claims reinforce wrong attributions.';

-- attribution_evidence_tier: the evidence quality tier when the span was attributed.
-- Values: 1 (strong anchor + high confidence >= 0.75), 2 (any anchor + medium
-- confidence >= 0.50), 3 (weak/no anchor or low confidence < 0.50).
-- Propagated from span_attributions.evidence_tier at claim creation time.
ALTER TABLE journal_claims
ADD COLUMN IF NOT EXISTS attribution_evidence_tier INTEGER
  CHECK (attribution_evidence_tier IN (1, 2, 3));

COMMENT ON COLUMN journal_claims.attribution_evidence_tier IS
  'Evidence quality tier at claim creation time (from span_attributions.evidence_tier). '
  'Tier 1 = strong anchor + high confidence. Tier 2 = any anchor + medium confidence. '
  'Tier 3 = weak/no anchor or low confidence. Context-assembly excludes tier 3 claims '
  'and marks tier 2 review claims as [UNVERIFIED] to prevent feedback loop contamination.';

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 2: INDEXES for context-assembly query performance
-- ──────────────────────────────────────────────────────────────────────────────

-- Composite index for the context-assembly query that filters active claims by
-- project + attribution quality. This is the hot path for breaking the loop.
CREATE INDEX IF NOT EXISTS idx_journal_claims_project_active_decision
ON journal_claims (project_id, attribution_decision, attribution_evidence_tier)
WHERE active = true;

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 3: BACKFILL from span_attributions for existing claims
-- ──────────────────────────────────────────────────────────────────────────────

-- Join journal_claims to span_attributions via source_span_id to propagate
-- the decision and evidence_tier that were in effect when each claim was created.
-- This covers the 2,691+ existing claims that lack this metadata.

UPDATE journal_claims jc
SET
  attribution_decision = sa.decision,
  attribution_evidence_tier = sa.evidence_tier
FROM span_attributions sa
WHERE jc.source_span_id = sa.span_id
  AND jc.attribution_decision IS NULL;

-- For claims where source_span_id is NULL (legacy claims created before the
-- source_span_id column existed), we cannot determine the attribution decision.
-- These remain NULL, which context-assembly should treat conservatively
-- (same as 'review' / tier 2 — surfaced but marked [UNVERIFIED]).

-- ──────────────────────────────────────────────────────────────────────────────
-- PART 4: TABLE-LEVEL COMMENT documenting the feedback loop fix
-- ──────────────────────────────────────────────────────────────────────────────

COMMENT ON TABLE journal_claims IS
  'Epistemic claims extracted from conversation spans by journal-extract. '
  'attribution_decision and attribution_evidence_tier columns (added 2026-02-15) '
  'propagate span attribution confidence to the claim level, enabling '
  'context-assembly to filter uncertain claims from journal context and break '
  'the feedback loop where review-tier attributions were reinforced by '
  'unqualified journal claims. See FIX_journal_context_query.sql for the '
  'corresponding context-assembly query fix.';
