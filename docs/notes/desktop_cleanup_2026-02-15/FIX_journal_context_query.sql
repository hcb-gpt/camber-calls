-- ============================================================================
-- FIX: Journal Context Query for context-assembly
-- PURPOSE: Break the feedback loop by filtering/tagging claims by attribution confidence
-- DATE: 2026-02-15
-- AUTHOR: DATA-1
-- ============================================================================
--
-- CONTEXT:
-- This query replaces the current context-assembly journal_claims fetch at
-- ~line 2188 of context-assembly/index.ts. The current query surfaces ALL
-- active claims for candidate projects with no regard for how confident the
-- original attribution was:
--
--   CURRENT (BROKEN):
--     .from("journal_claims")
--     .select("project_id, call_id, claim_type, claim_text, epistemic_status, created_at")
--     .in("project_id", candidateProjectIds)
--     .eq("active", true)
--     .order("created_at", { ascending: false })
--     .limit(candidateProjectIds.length * 25)
--
-- THE PROBLEM:
-- Claims created from 'review' decision spans (confidence 0.50-0.74) look
-- identical to claims from 'assign' decision spans (confidence >= 0.75).
-- When context-assembly surfaces these uncertain claims as journal context,
-- future ai-router runs see them as confirmation of the uncertain project
-- attribution — creating a positive feedback loop that locks in wrong projects.
--
-- THE FIX:
-- Three-tier filtering based on attribution_decision + attribution_evidence_tier:
--
-- TIER A (Full confidence — surfaced as-is):
--   attribution_decision = 'assign' OR attribution_evidence_tier = 1
--   These are high-quality attributions. Safe to present as journal context.
--
-- TIER B (Uncertain — surfaced with [UNVERIFIED] tag):
--   attribution_decision = 'review' AND attribution_evidence_tier != 3
--   Also: attribution_decision IS NULL (legacy claims, treat conservatively)
--   These may be correct but aren't confirmed. Tagging them as [UNVERIFIED]
--   gives the ai-router a signal to discount them rather than treating them
--   as ground truth.
--
-- TIER C (Excluded — too uncertain to inform future decisions):
--   attribution_evidence_tier = 3
--   These had weak/no anchors and low confidence. Surfacing them as context
--   would only inject noise and reinforce wrong attributions.
--
-- ============================================================================


-- ============================================================================
-- QUERY A: Raw SQL version (for reference / direct DB use)
-- ============================================================================
-- This is the canonical SQL. The Supabase JS client version follows below.
--
-- Parameters:
--   $1 = array of candidate project IDs (uuid[])
--   $2 = per-project claim limit (integer, e.g. 25 * number of candidates)

SELECT
  jc.project_id,
  jc.call_id,
  jc.claim_type,
  -- Tag uncertain claims so ai-router knows they are not confirmed facts.
  -- This is the key mechanism that breaks the feedback loop: the router can
  -- see that this claim's project attribution was never confirmed.
  CASE
    WHEN jc.attribution_decision = 'assign' OR jc.attribution_evidence_tier = 1
      THEN jc.claim_text
    WHEN jc.attribution_decision IS NULL
      THEN '[UNVERIFIED] ' || jc.claim_text
    WHEN jc.attribution_decision = 'review'
      THEN '[UNVERIFIED] ' || jc.claim_text
    ELSE jc.claim_text  -- should not happen; defensive
  END AS claim_text,
  jc.epistemic_status,
  jc.created_at,
  -- Expose decision metadata so downstream can make its own filtering choices
  jc.attribution_decision,
  jc.attribution_evidence_tier
FROM journal_claims jc
WHERE jc.project_id = ANY($1)
  AND jc.active = true
  -- EXCLUDE tier 3 claims entirely: too uncertain to inform future decisions.
  -- This is the hard filter that prevents the worst feedback loop cases.
  AND (jc.attribution_evidence_tier IS NULL OR jc.attribution_evidence_tier < 3)
ORDER BY jc.created_at DESC
LIMIT $2;


-- ============================================================================
-- QUERY B: Supabase JS client version (for context-assembly/index.ts)
-- ============================================================================
-- Replace the current fetch at ~line 2188 with this code block.
-- The [UNVERIFIED] tagging is done in the TypeScript processing loop below
-- since Supabase JS .select() doesn't support CASE expressions.
--
-- ```typescript
-- // ── FEEDBACK LOOP FIX (2026-02-15) ─────────────────────────────
-- // Filter claims by attribution confidence to prevent uncertain
-- // claims from reinforcing wrong project attributions.
-- // Tier 3 claims (weak/no anchor, low confidence) are excluded entirely.
-- // Tier 2 / review claims are tagged [UNVERIFIED] in the processing loop.
-- const { data: claimsData, error: claimsErr } = await db
--   .from("journal_claims")
--   .select("project_id, call_id, claim_type, claim_text, epistemic_status, created_at, attribution_decision, attribution_evidence_tier")
--   .in("project_id", candidateProjectIds)
--   .eq("active", true)
--   // HARD FILTER: exclude tier 3 claims (too uncertain for journal context)
--   .or("attribution_evidence_tier.is.null,attribution_evidence_tier.lt.3")
--   .order("created_at", { ascending: false })
--   .limit(candidateProjectIds.length * 25);
-- ```
--
-- Then in the claim processing loop (~line 2242), replace:
--   arr.push({
--     claim_type: c.claim_type,
--     claim_text: (c.claim_text || "").slice(0, 200),
--     epistemic_status: c.epistemic_status,
--     created_at: c.created_at,
--   });
--
-- With:
-- ```typescript
-- // ── FEEDBACK LOOP FIX: Tag uncertain claims ────────────────────
-- // Claims from 'assign' decisions or evidence_tier=1 are full-confidence.
-- // Claims from 'review' decisions, NULL decisions (legacy), or
-- // evidence_tier=2 are tagged [UNVERIFIED] so the ai-router knows
-- // not to treat them as confirmed project facts.
-- const isConfirmed =
--   c.attribution_decision === 'assign' ||
--   c.attribution_evidence_tier === 1;
-- const claimText = (c.claim_text || "").slice(0, 200);
-- const taggedText = isConfirmed ? claimText : `[UNVERIFIED] ${claimText}`;
--
-- arr.push({
--   claim_type: c.claim_type,
--   claim_text: taggedText,
--   epistemic_status: c.epistemic_status,
--   created_at: c.created_at,
-- });
-- ```


-- ============================================================================
-- QUERY C: Diagnostic query — measure feedback loop contamination
-- ============================================================================
-- Run this to see how many active claims fall into each tier.
-- This quantifies the scope of the feedback loop problem.

SELECT
  COALESCE(jc.attribution_decision, 'NULL (legacy)') AS decision,
  COALESCE(jc.attribution_evidence_tier::text, 'NULL') AS evidence_tier,
  COUNT(*) AS claim_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct
FROM journal_claims jc
WHERE jc.active = true
GROUP BY jc.attribution_decision, jc.attribution_evidence_tier
ORDER BY claim_count DESC;


-- ============================================================================
-- QUERY D: Verify the fix — compare old vs new context assembly output
-- ============================================================================
-- For a given project, show what the old query would surface vs what the new
-- query surfaces (with tagging).

-- Old behavior (surfaces everything, no confidence awareness):
-- SELECT count(*) AS old_claim_count
-- FROM journal_claims
-- WHERE project_id = '<project_uuid>'
--   AND active = true;

-- New behavior (excludes tier 3, tags uncertain):
-- SELECT
--   count(*) FILTER (WHERE attribution_decision = 'assign' OR attribution_evidence_tier = 1) AS confirmed_claims,
--   count(*) FILTER (WHERE attribution_decision = 'review' OR attribution_decision IS NULL) AS unverified_claims,
--   count(*) FILTER (WHERE attribution_evidence_tier = 3) AS excluded_claims
-- FROM journal_claims
-- WHERE project_id = '<project_uuid>'
--   AND active = true;


-- ============================================================================
-- IMPORTANT: journal-extract MUST ALSO be updated
-- ============================================================================
-- In addition to these query changes, journal-extract/index.ts (~line 706-739)
-- must propagate attribution_decision and attribution_evidence_tier when
-- creating new claims. Add these fields to the claimRows map:
--
-- ```typescript
-- // ── FEEDBACK LOOP FIX: Propagate attribution confidence to claims ──
-- attribution_decision: attribution?.decision || null,
-- attribution_evidence_tier: (() => {
--   // Mirror the deriveEvidenceTier logic from ai-router:
--   // Tier 1 = strong anchor + high confidence >= 0.75
--   // Tier 2 = any anchor + medium confidence >= 0.50
--   // Tier 3 = weak/no anchor or low confidence < 0.50
--   // Since journal-extract doesn't have anchor data, we derive from
--   // the decision + confidence that span_attributions already computed.
--   const conf = attribution?.confidence ?? 0;
--   const decision = attribution?.decision;
--   if (decision === 'assign' && conf >= 0.75) return 1;
--   if (decision !== 'none' && conf >= 0.50) return 2;
--   return 3;
-- })(),
-- ```
--
-- This ensures newly created claims carry their confidence metadata from
-- creation, not just from the backfill. The backfill (in the migration) handles
-- the 2,691+ existing claims; this code handles all future claims.
