/**
 * ai-router Edge Function v1.12.0
 * LLM-based project attribution for conversation spans
 *
 * @version 1.12.0
 * @date 2026-02-15
 * @purpose Use Claude Haiku to attribute spans to projects with anchored evidence
 *
 * CORE PRINCIPLE: span_attributions is the single source of truth.
 * NO writes to interactions.project_id from this path.
 *
 * v1.12.0 Changes (closed-project hard filter + resegment invariant + early-span coherence):
 * - Enforces closed-project hard filter pre-inference (candidate list) and post-inference
 *   (chosen project status check) to prevent closed-project leakage.
 * - Adds auto-resegment invariant: span_chars > 3000 OR multiple strong-anchor projects
 *   returns 409 + triggers admin-reseed resegment_and_reroute path.
 * - Adds adjacent-span coherence guard for spans 0-3: prevent project hops without
 *   transcript switch signal by overriding to coherent prior project (or downgrading review).
 *
 * v1.11.1 Changes (homeowner override strong-anchor equivalence):
 * - Treats context_package.meta.homeowner_override=true (without contradiction metadata)
 *   as a strong-anchor equivalent for gating/review-queue reason generation.
 * - Prevents weak_anchor / geo_only review reasons for deterministic homeowner overrides
 *   unless explicit contradiction metadata is present.
 *
 * v1.11.0 Changes (bizdev/prospect commitment gate):
 * - Added bizdev/prospect classifier with evidence tags from transcript terms
 * - Added commitment-to-start gate: bizdev spans cannot retain project_id without
 *   commitment evidence (contract/deposit/permit/PO/start-date language)
 * - Added bizdev classifier details to review_queue context + API response guardrails
 *
 * v1.10.0 Changes (common-word alias corroboration guardrail):
 * - Added guardrail to downgrade assign->review when chosen project is supported
 *   only by common-word/material aliases (for example "white", "mystery white")
 * - Prompt now explicitly forbids auto-assign on uncorroborated common aliases
 * - Candidate prompt includes aliases that are treated as ambiguous/common-word
 * - Review queue reason codes now include common_alias_unconfirmed when triggered
 *
 * v1.9.0 Changes (source_strength in Evidence line):
 * - Prompt now includes source_strength per candidate in the Evidence line
 *   (was missing — LLM never saw transcript evidence quality scores)
 * - ContextPackage type updated to include source_strength field
 * - Prompt version bumped to v1.9.0 (content change)
 * - Pairs with context-assembly v2.1.0 sort fix (source_strength > affinity_weight)
 *
 * v1.8.1 Changes (Pipeline chain wiring):
 * - Added fire-and-forget chain call to journal-extract after span_attributions write
 *   (belt-and-suspenders with segment-call hook — ensures journal extraction runs
 *   even when ai-router is called outside the segment-call chain, e.g. backfill/replay)
 * - journal-extract fires for ALL decisions (assign/review/none) since it reads
 *   applied_project_id from span_attributions and handles null-project gracefully
 * - Response includes journal_extract_fired flag + function_version field
 *
 * v1.8.0 Changes (Gmail weak corroboration):
 * - Prompt includes bounded email_context summaries when present
 * - Explicitly treats email context as weak corroboration only
 *
 * v1.7.0 Changes (P1: Contact Fanout + Journal References):
 * - Prompt includes fanout_class + effective_fanout per contact (DATA-9 D4 spec)
 * - Prompt explains fanout signal strength (anchored=strong, floater=anti-signal)
 * - Output includes journal_references: which journal claims influenced the decision
 * - Replaces boolean floater_flag with richer fanout context
 *
 * Input:
 *   - context_package: ContextPackage (from context-assembly)
 *   - dry_run?: boolean (if true, don't persist to DB)
 *
 * Output:
 *   - span_id, project_id, confidence, decision, reasoning, anchors
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@0.39.0";
import { parseLlmJson } from "../_shared/llm_json.ts";
import { applyCommonAliasCorroborationGuardrail, isCommonWordAlias } from "./alias_guardrails.ts";
import { applyBizDevCommitmentGate } from "./bizdev_guardrails.ts";
import { homeownerOverrideActsAsStrongAnchor } from "./homeowner_override_gate.ts";
import { evaluateAutoResegmentInvariant } from "./resegment_guardrails.ts";
import { evaluateAdjacentSpanCoherence } from "./adjacent_coherence_guardrails.ts";

const PROMPT_VERSION = "v1.11.0"; // prompt unchanged since v1.11.0
const FUNCTION_VERSION = "v1.12.0";
const MODEL_ID = "claude-3-haiku-20240307";
const MAX_TOKENS = 1024;

// Confidence thresholds
const THRESHOLD_AUTO_ASSIGN = 0.75;
const THRESHOLD_REVIEW = 0.50;
const ATTRIBUTION_ELIGIBLE_PROJECT_STATUSES = new Set(["active", "warranty", "estimating"]);
const ATTRIBUTION_ELIGIBLE_PROJECT_KIND = "client";
const AUTO_RESEGMENT_IDEMPOTENCY_VERSION = "v2";

// ============================================================
// TYPES
// ============================================================

interface Anchor {
  text: string;
  candidate_project_id: string | null;
  match_type: string;
  quote: string;
}

type PlaceRole = "proximity" | "origin" | "destination";

interface GeoSignal {
  score: number;
  dominant_role: PlaceRole;
  role_counts: Record<PlaceRole, number>;
  place_count: number;
}

interface PlaceMention {
  place_name: string;
  geo_place_id: string | null;
  lat: number | null;
  lon: number | null;
  role: PlaceRole;
  trigger_verb: string | null;
  char_offset: number;
  snippet: string;
}

interface SuggestedAlias {
  project_id: string;
  alias_term: string;
  rationale: string;
}

interface JournalReference {
  project_id: string;
  claim_type: string;
  claim_text: string;
  relevance: string;
}

interface AttributionResult {
  span_id: string;
  project_id: string | null;
  confidence: number;
  decision: "assign" | "review" | "none";
  reasoning: string;
  anchors: Anchor[];
  suggested_aliases?: SuggestedAlias[];
  journal_references?: JournalReference[];
}

interface JournalClaim {
  claim_type: string;
  claim_text: string;
  epistemic_status: string;
  created_at: string;
}

interface JournalOpenLoop {
  loop_type: string;
  description: string;
  status: string;
}

interface ProjectJournalState {
  project_id: string;
  active_claims_count: number;
  recent_claims: JournalClaim[];
  open_loops: JournalOpenLoop[];
  last_journal_activity: string | null;
}

interface EmailContextItem {
  message_id: string;
  thread_id: string | null;
  date: string | null;
  from: string | null;
  to: string | null;
  subject: string | null;
  subject_keywords: string[];
  project_mentions: string[];
  mentioned_project_ids: string[];
  amounts_mentioned: string[];
  evidence_locator: string;
}

interface EmailLookupMeta {
  returned_count?: number;
  cached?: boolean;
  warnings?: string[];
  date_range?: string | null;
}

interface ContextPackage {
  meta: {
    span_id: string;
    interaction_id: string;
    [key: string]: any;
  };
  span: {
    transcript_text: string;
    [key: string]: any;
  };
  contact: {
    contact_id: string | null;
    contact_name: string | null;
    floater_flag: boolean;
    fanout_class?: string;
    effective_fanout?: number;
    recent_projects: Array<{ project_id: string; project_name: string }>;
  };
  candidates: Array<{
    project_id: string;
    project_name: string;
    address: string | null;
    client_name: string | null;
    aliases: string[];
    status: string | null;
    phase: string | null;
    evidence: {
      sources: string[];
      affinity_weight: number;
      source_strength?: number;
      assigned: boolean;
      alias_matches: Array<{ term: string; match_type: string; snippet?: string }>;
      geo_distance_km?: number;
      geo_signal?: GeoSignal;
    };
  }>;
  place_mentions?: PlaceMention[];
  project_journal?: ProjectJournalState[];
  email_context?: EmailContextItem[];
  email_lookup_meta?: EmailLookupMeta | null;
}

// ============================================================
// GUARDRAIL HELPERS
// ============================================================

const HCB_STAFF_PATTERNS = [
  "zack sittler",
  "zachary sittler",
  "zach sittler",
  "chad barlow",
  "sittler:",
];

function anchorContainsStaffName(quote: string): boolean {
  const quoteLower = (quote || "").toLowerCase();
  for (const pattern of HCB_STAFF_PATTERNS) {
    if (quoteLower.includes(pattern)) {
      return true;
    }
  }
  if (/\bsittler\b/i.test(quote) && !/residence|project|house/i.test(quote)) {
    return true;
  }
  return false;
}

function normalizeForQuoteMatch(text: string): string {
  return (text || "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[“”„‟‘’`"]/g, "")
    .replace(/[\-–—]/g, " ")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokenizeForQuoteMatch(text: string): string[] {
  return normalizeForQuoteMatch(text)
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
}

function levenshteinDistanceWithLimit(a: string, b: string, maxDistance: number): number {
  if (a.length === 0) return Math.min(b.length, maxDistance + 1);
  if (b.length === 0) return Math.min(a.length, maxDistance + 1);
  if (Math.abs(a.length - b.length) > maxDistance) return maxDistance + 1;

  const row = new Int32Array(b.length + 1);
  const prevRow = new Int32Array(b.length + 1);

  for (let j = 0; j <= b.length; j++) {
    prevRow[j] = j;
  }

  for (let i = 1; i <= a.length; i++) {
    row[0] = i;
    let bestInRow = row[0];

    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      const value = Math.min(
        prevRow[j] + 1,
        row[j - 1] + 1,
        prevRow[j - 1] + cost,
      );
      row[j] = value;
      if (value < bestInRow) bestInRow = value;
    }

    if (bestInRow > maxDistance) {
      return maxDistance + 1;
    }

    prevRow.set(row);
  }

  return prevRow[b.length];
}

function hasFuzzyMatch(
  haystackTokens: string[],
  quoteNorm: string,
  quoteTokens: string[],
): boolean {
  const maxWindowDelta = Math.max(1, Math.floor(quoteTokens.length * 0.25));
  const minWindowLen = Math.max(1, quoteTokens.length - maxWindowDelta);
  const maxWindowLen = Math.min(haystackTokens.length, quoteTokens.length + maxWindowDelta);

  const maxDistance = Math.max(3, Math.floor(quoteNorm.length * 0.18));

  for (let windowLen = minWindowLen; windowLen <= maxWindowLen; windowLen++) {
    for (let i = 0; i + windowLen <= haystackTokens.length; i++) {
      const candidate = haystackTokens.slice(i, i + windowLen).join(" ");
      const distance = levenshteinDistanceWithLimit(quoteNorm, candidate, maxDistance);
      if (distance <= maxDistance) {
        return true;
      }
    }
  }

  return false;
}

function validateAnchorQuotes(
  anchors: Anchor[],
  transcript: string,
): { valid: boolean; validatedAnchors: Anchor[]; rejectedStaffAnchors: number } {
  if (!transcript || !anchors.length) {
    return { valid: false, validatedAnchors: [], rejectedStaffAnchors: 0 };
  }

  const transcriptNorm = normalizeForQuoteMatch(transcript);
  const transcriptTokens = tokenizeForQuoteMatch(transcriptNorm);

  const validatedAnchors: Anchor[] = [];
  let rejectedStaffAnchors = 0;

  for (const anchor of anchors) {
    if (!anchor.quote || anchor.quote.length === 0) continue;

    const quoteNorm = normalizeForQuoteMatch(anchor.quote);
    if (quoteNorm.length < 3) continue;

    if (anchorContainsStaffName(anchor.quote) || anchorContainsStaffName(anchor.text || "")) {
      rejectedStaffAnchors++;
      console.log(`[ai-router] Rejected staff-name anchor: "${anchor.quote}"`);
      continue;
    }

    const quoteTokens = tokenizeForQuoteMatch(quoteNorm);
    const exactMatch = transcriptNorm.includes(quoteNorm);
    const fuzzyMatch = !exactMatch && quoteTokens.length >= 3
      ? hasFuzzyMatch(transcriptTokens, quoteNorm, quoteTokens)
      : false;

    if (!exactMatch && !fuzzyMatch) {
      console.log(`[ai-router] Rejected anchor: quote not in transcript: "${anchor.quote}"`);
      continue;
    }

    const textNorm = normalizeForQuoteMatch(anchor.text || "");
    if (textNorm.length >= 3 && !quoteNorm.includes(textNorm)) {
      console.log(`[ai-router] Rejected anchor: text "${anchor.text}" not found in quote "${anchor.quote}"`);
      continue;
    }

    validatedAnchors.push(anchor);
  }

  return {
    valid: validatedAnchors.length > 0,
    validatedAnchors,
    rejectedStaffAnchors,
  };
}

const STRONG_ANCHOR_TYPES = [
  "exact_project_name",
  "alias",
  "address_fragment",
  "client_name",
];

const _WEAK_ANCHOR_TYPES = [
  "city_or_location",
  "mentioned_contact",
  "phonetic_or_pronunciation",
  "continuity_callback",
  "db_scan",
  "other",
];

function hasStrongAnchor(anchors: Anchor[]): boolean {
  return anchors.some((a) => STRONG_ANCHOR_TYPES.includes(a.match_type));
}

/**
 * Derive attribution_source from anchor composition.
 * Values: llm_strong_anchor, llm_weak_anchor, llm_no_anchor, model_error
 */
function deriveAttributionSource(anchors: Anchor[], modelError: boolean): string {
  if (modelError) return "model_error";
  if (!anchors || anchors.length === 0) return "llm_no_anchor";
  if (hasStrongAnchor(anchors)) return "llm_strong_anchor";
  return "llm_weak_anchor";
}

/**
 * Derive evidence_tier from anchor strength + confidence.
 * Tier 1 = strong anchor + high confidence (>= 0.75)
 * Tier 2 = any anchor + medium confidence (>= 0.50)
 * Tier 3 = weak/no anchor or low confidence (< 0.50)
 */
function deriveEvidenceTier(anchors: Anchor[], confidence: number, modelError: boolean): number {
  if (modelError) return 3;
  const strong = hasStrongAnchor(anchors);
  if (strong && confidence >= 0.75) return 1;
  if (anchors.length > 0 && confidence >= 0.50) return 2;
  return 3;
}

function isAttributionEligibleProject(status: string | null | undefined, projectKind?: string | null): boolean {
  const normalizedStatus = String(status || "").trim().toLowerCase();
  if (!ATTRIBUTION_ELIGIBLE_PROJECT_STATUSES.has(normalizedStatus)) return false;
  if (projectKind != null && String(projectKind || "").trim().toLowerCase() !== ATTRIBUTION_ELIGIBLE_PROJECT_KIND) {
    return false;
  }
  return true;
}

function filterClosedProjectCandidates(ctx: ContextPackage): {
  filtered: ContextPackage;
  removed_count: number;
} {
  const candidates = Array.isArray(ctx.candidates) ? ctx.candidates : [];
  const filteredCandidates = candidates.filter((c) => isAttributionEligibleProject(c.status));
  const removedCount = candidates.length - filteredCandidates.length;
  if (removedCount <= 0) {
    return { filtered: ctx, removed_count: 0 };
  }

  const existingWarnings = Array.isArray(ctx.meta?.warnings) ? ctx.meta.warnings : [];
  return {
    filtered: {
      ...ctx,
      meta: {
        ...(ctx.meta || {}),
        warnings: [...existingWarnings, `closed_project_filtered_router:${removedCount}`],
      },
      candidates: filteredCandidates,
    },
    removed_count: removedCount,
  };
}

function normalizeAnchorTerm(term: string): string {
  return String(term || "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function inferStrongProjectIdsFromCandidates(candidates: ContextPackage["candidates"]): string[] {
  const projectIds = new Set<string>();
  for (const candidate of candidates || []) {
    const normalizedAliases = new Set<string>();
    for (const alias of candidate.aliases || []) {
      const norm = normalizeAnchorTerm(alias);
      if (norm) normalizedAliases.add(norm);
    }
    const projectNameNorm = normalizeAnchorTerm(candidate.project_name || "");
    if (projectNameNorm) normalizedAliases.add(projectNameNorm);

    const hasStrongSignal = (candidate.evidence?.alias_matches || []).some((m) => {
      const matchType = String(m.match_type || "");
      if (STRONG_ANCHOR_TYPES.includes(matchType)) return true;
      if (matchType !== "city_or_location") return false;
      const termNorm = normalizeAnchorTerm(String(m.term || ""));
      if (!termNorm || termNorm.length < 5) return false;
      return normalizedAliases.has(termNorm);
    });

    if (hasStrongSignal && candidate.project_id) {
      projectIds.add(candidate.project_id);
    }
  }
  return Array.from(projectIds);
}

async function fetchPriorAssignedProjects(
  db: any,
  interactionId: string | null,
  spanIndex: number,
): Promise<string[]> {
  if (!interactionId || spanIndex < 1 || spanIndex > 3) return [];

  const { data: priorSpans, error: priorErr } = await db
    .from("conversation_spans")
    .select("id, span_index")
    .eq("interaction_id", interactionId)
    .eq("is_superseded", false)
    .lt("span_index", spanIndex)
    .order("span_index", { ascending: false })
    .limit(3);

  if (priorErr || !priorSpans?.length) return [];

  const priorSpanIds = priorSpans.map((s: any) => s.id).filter(Boolean);
  if (priorSpanIds.length === 0) return [];

  const { data: attribRows, error: attribErr } = await db
    .from("span_attributions")
    .select("span_id, project_id, applied_project_id, decision, confidence, attributed_at")
    .in("span_id", priorSpanIds)
    .order("attributed_at", { ascending: false });

  if (attribErr || !attribRows?.length) return [];

  const latestBySpan = new Map<string, any>();
  for (const row of attribRows) {
    if (!row.span_id || latestBySpan.has(row.span_id)) continue;
    latestBySpan.set(row.span_id, row);
  }

  const orderedPrior = priorSpans
    .slice()
    .sort((a: any, b: any) => Number(a.span_index || 0) - Number(b.span_index || 0));
  const assignedProjectIds: string[] = [];
  for (const s of orderedPrior) {
    const row = latestBySpan.get(s.id);
    if (!row) continue;
    const appliedProjectId = row.applied_project_id || row.project_id || null;
    if (row.decision === "assign" && appliedProjectId) {
      assignedProjectIds.push(appliedProjectId);
    }
  }
  return assignedProjectIds;
}

async function triggerAutoReseed(params: {
  interaction_id: string | null;
  reason: string;
}): Promise<{ dispatched: boolean; status: number | null; detail: string | null }> {
  if (!params.interaction_id) {
    return { dispatched: false, status: null, detail: "missing_interaction_id" };
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!supabaseUrl || !edgeSecret) {
    return { dispatched: false, status: null, detail: "missing_runtime_env" };
  }

  const reseedUrl = `${supabaseUrl}/functions/v1/admin-reseed`;
  const idempotencyKey = `ai-router:auto-resegment:${params.interaction_id}:${AUTO_RESEGMENT_IDEMPOTENCY_VERSION}`;
  try {
    const resp = await fetch(reseedUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Edge-Secret": edgeSecret,
        "X-Source": "system",
      },
      body: JSON.stringify({
        interaction_id: params.interaction_id,
        reason: params.reason,
        idempotency_key: idempotencyKey,
        mode: "resegment_and_reroute",
        requested_by: "system",
      }),
    });

    if (!resp.ok) {
      const bodyText = await resp.text().catch(() => "unknown");
      return { dispatched: false, status: resp.status, detail: bodyText.slice(0, 200) };
    }

    return { dispatched: true, status: resp.status, detail: null };
  } catch (e: any) {
    return { dispatched: false, status: null, detail: e?.message || "unknown_error" };
  }
}

function canOverwriteLock(currentLock: string | null, newLock: string | null): boolean {
  const lockOrder: Record<string, number> = { "human": 3, "ai": 2 };
  const currentLevel = lockOrder[currentLock || ""] || 0;
  const newLevel = lockOrder[newLock || ""] || 0;
  return newLevel >= currentLevel;
}

// ============================================================
// REVIEW QUEUE HELPERS (PR-4)
// ============================================================

function buildReasonCodes(opts: {
  modelReasons?: string[] | null;
  quoteVerified: boolean;
  strongAnchor: boolean;
  modelError?: boolean;
  ambiguousContact?: boolean;
  geoOnly?: boolean;
  commonAliasUnconfirmed?: boolean;
  bizdevWithoutCommitment?: boolean;
  coherenceGuardrail?: boolean;
  closedProjectGuardrail?: boolean;
}): string[] {
  const reasons: string[] = [];
  if (Array.isArray(opts.modelReasons)) reasons.push(...opts.modelReasons);

  if (!opts.quoteVerified) reasons.push("quote_unverified");
  if (!opts.strongAnchor) reasons.push("weak_anchor");
  if (opts.ambiguousContact) reasons.push("ambiguous_contact");
  if (opts.geoOnly) reasons.push("geo_only");
  if (opts.commonAliasUnconfirmed) reasons.push("common_alias_unconfirmed");
  if (opts.bizdevWithoutCommitment) reasons.push("bizdev_without_commitment");
  if (opts.coherenceGuardrail) reasons.push("adjacent_span_coherence");
  if (opts.closedProjectGuardrail) reasons.push("closed_project_filtered");
  if (opts.modelError) reasons.push("model_error");

  return Array.from(new Set(reasons.filter(Boolean)));
}

async function upsertReviewQueue(
  db: any,
  payload: {
    span_id: string;
    interaction_id: string;
    reasons: string[];
    context_payload: Record<string, unknown>;
  },
) {
  const { error } = await db
    .from("review_queue")
    .upsert(
      {
        span_id: payload.span_id,
        interaction_id: payload.interaction_id,
        status: "pending",
        reason_codes: payload.reasons,
        reasons: payload.reasons,
        context_payload: payload.context_payload,
      },
      { onConflict: "span_id" },
    );

  if (error) {
    console.error("[ai-router] review_queue upsert failed:", error.message);
  }
}

async function resolveReviewQueue(
  db: any,
  spanId: string,
  notes: string,
) {
  const { error } = await db
    .from("review_queue")
    .update({
      status: "resolved",
      resolved_at: new Date().toISOString(),
      resolved_by: "ai-router",
      resolution_action: "confirmed",
      resolution_notes: notes,
    })
    .eq("span_id", spanId)
    .eq("status", "pending");

  if (error) {
    console.error("[ai-router] review_queue resolve failed:", error.message);
  }
}

// ============================================================
// PROMPT TEMPLATE
// ============================================================

const SYSTEM_PROMPT =
  `You are a project attribution specialist for HCB (Heartwood Custom Builders), a Georgia construction company.
Given a phone call transcript segment and candidate projects, determine which project (if any) the conversation is about.

CRITICAL - HCB STAFF EXCLUSION (HIGHEST PRIORITY):
The following are HCB STAFF/OWNERS who appear on MANY calls. They are NOT project clients:
- "Zack Sittler", "Zachary Sittler", "Zach Sittler" (owner/general contractor)
- "Chad Barlow" (owner)
- The word "Sittler" alone, when it refers to Zack

STRICT RULES FOR STAFF NAMES:
1. NEVER use any HCB staff name as an anchor quote
2. NEVER match staff names to similarly-named projects (e.g., "Sittler" in transcript does NOT indicate "Sittler Residence" project)
3. If the ONLY evidence for a project is a staff name match, output decision="review" or decision="none"
4. Speaker labels like "Zachary Sittler:" are NOT project evidence - they just identify who is speaking

RULES:
1. Look for explicit mentions of project names, addresses (including partial addresses like street names), CLIENT names (not staff), or known aliases in the transcript
2. The caller's project assignments (assigned=true) and call history (affinity) are SECONDARY signals - use them only when transcript evidence is ambiguous
3. CONTACT FANOUT determines how much weight to give the contact's identity:
   - anchored (fanout=1): Contact works on ONE project. Their identity is a STRONG attribution signal (near smoking gun)
   - semi_anchored (fanout=2): Useful with corroboration from transcript
   - drifter (fanout=3-4): Contextual only, needs strong transcript grounding
   - floater (fanout>=5): ANTI-SIGNAL. Treat like HCB staff for attribution — prioritize transcript anchors only
   - unknown (fanout=0): No project association — no signal from identity
4. If multiple projects are mentioned, choose the PRIMARY topic of discussion
5. If uncertain, choose "review" with confidence 0.50-0.74
6. If no clear project match exists in the transcript, choose "none" with confidence <0.50
7. Common-word/material aliases (for example color/material terms like "white", "mystery white", "granite") are ambiguous and CANNOT be sole evidence for decision="assign"
8. If a common-word alias appears, require corroboration in transcript from exact project name, address fragment, or client name before decision="assign"

PROJECT JOURNAL CONTEXT (when available):
Some candidate projects may include journal state — recent claims, decisions,
commitments, and open loops extracted from prior calls. Use this context to inform
your reasoning:
- If the transcript discusses a topic matching an open loop or recent commitment
  for a project, that's corroborating evidence for attribution to that project
- If someone references a deadline or decision that appears in a project's journal,
  that strengthens the match
- Journal context is SUPPLEMENTARY — it does not replace transcript-grounded anchors
- A project with rich journal activity matching the conversation topic is more
  likely the correct attribution than one with no prior context

EMAIL CONTEXT (when available):
- Email context is WEAK corroboration only (subject keywords, mentions, amounts).
- Never auto-assign based only on email context.
- Use email context to break ties only when transcript-grounded anchors already exist.
- If email context conflicts with transcript anchors, trust the transcript.

GEO CONTEXT (when available):
- Geo signals are WEAK corroboration only (distance + role + place mentions).
- Never auto-assign based only on geo/proximity evidence.
- Destination/origin roles can increase confidence inside review band when transcript anchors already exist.
- If geo conflicts with strong transcript anchors, trust transcript anchors.

CONFIDENCE THRESHOLDS:
- 0.75-1.00: Strong transcript-grounded evidence, safe to auto-assign
- 0.50-0.74: Moderate evidence, needs human review
- 0.00-0.49: Weak/no evidence, no assignment

ANCHOR STRENGTH POLICY:
To use decision="assign", you MUST have at least one STRONG anchor type:
- STRONG: exact_project_name, alias, address_fragment, client_name
- WEAK: city_or_location, mentioned_contact, phonetic_or_pronunciation, continuity_callback, other

If your ONLY evidence is weak anchors (e.g., city name, zip code, county), you MUST use decision="review".
City/location matches alone are NEVER sufficient for auto-assign because multiple projects may share the same city.

CRITICAL GUARDRAIL:
To output decision="assign", you MUST provide at least one anchor with an EXACT QUOTE from the transcript in the "quote" field.
If you cannot find a direct quote supporting the attribution, you MUST use decision="review" or decision="none".

OUTPUT FORMAT (JSON only, no markdown):
{
  "project_id": "<uuid or null>",
  "confidence": <0.00-1.00>,
  "decision": "assign|review|none",
  "reasoning": "<1-3 sentences explaining the decision>",
  "anchors": [
    {
      "text": "<the matched term/phrase>",
      "candidate_project_id": "<uuid of the project this evidence supports>",
      "match_type": "<exact_project_name|alias|address_fragment|city_or_location|client_name|mentioned_contact|phonetic_or_pronunciation|continuity_callback|other>",
      "quote": "<EXACT quote from transcript, max 50 chars>"
    }
  ],
  "journal_references": [
    {
      "project_id": "<uuid>",
      "claim_type": "<claim type from journal>",
      "claim_text": "<the journal claim that influenced your decision>",
      "relevance": "<how this claim relates to the transcript>"
    }
  ],
  "suggested_aliases": [
    {
      "project_id": "<uuid>",
      "alias_term": "<new alias to add>",
      "rationale": "<why this should be an alias>"
    }
  ]
}

IMPORTANT: The "quote" field in anchors must contain text that ACTUALLY APPEARS in the transcript segment provided.`;

function buildUserPrompt(ctx: ContextPackage): string {
  const journalByProject = new Map<string, ProjectJournalState>();
  if (ctx.project_journal && Array.isArray(ctx.project_journal)) {
    for (const pj of ctx.project_journal) {
      journalByProject.set(pj.project_id, pj);
    }
  }

  const candidateList = ctx.candidates.map((c, i) => {
    const aliasMatchSummary = c.evidence.alias_matches.length > 0
      ? `Matches in transcript: ${c.evidence.alias_matches.map((m) => `"${m.term}" (${m.match_type})`).join(", ")}`
      : "No direct transcript matches";
    const commonAliases = c.aliases.filter((alias) => isCommonWordAlias(alias)).slice(0, 5);

    const geoSummary = c.evidence.geo_signal
      ? `Geo: distance=${
        typeof c.evidence.geo_distance_km === "number" ? `${c.evidence.geo_distance_km.toFixed(1)}km` : "n/a"
      }, score=${
        c.evidence.geo_signal.score.toFixed(2)
      }, role=${c.evidence.geo_signal.dominant_role}, places=${c.evidence.geo_signal.place_count}`
      : "Geo: none";

    const journalState = journalByProject.get(c.project_id);
    let journalSummary = "   - Journal: No prior context";
    if (journalState && (journalState.recent_claims.length > 0 || journalState.open_loops.length > 0)) {
      const claimsSummary = journalState.recent_claims.slice(0, 3).map(
        (cl) => `[${cl.claim_type}] ${cl.claim_text}`,
      ).join("; ");
      const loopsSummary = journalState.open_loops.map(
        (l) => `[${l.loop_type}] ${l.description}`,
      ).join("; ");
      journalSummary = `   - Journal (${journalState.active_claims_count} active claims):`;
      if (claimsSummary) journalSummary += `\n     Recent: ${claimsSummary}`;
      if (loopsSummary) journalSummary += `\n     Open loops: ${loopsSummary}`;
    }

    return `${i + 1}. ${c.project_name}
   - ID: ${c.project_id}
   - Address: ${c.address || "N/A"}
   - Client: ${c.client_name || "N/A"}
   - Aliases: ${c.aliases.length > 0 ? c.aliases.slice(0, 5).join(", ") : "None"}
   - Common-word aliases (need corroboration): ${commonAliases.length > 0 ? commonAliases.join(", ") : "None"}
   - Status: ${c.status || "N/A"}, Phase: ${c.phase || "N/A"}
   - Evidence: assigned=${c.evidence.assigned}, affinity=${c.evidence.affinity_weight.toFixed(2)}, source_strength=${
      (c.evidence.source_strength ?? 0).toFixed(2)
    }, sources=[${c.evidence.sources.join(",")}]
   - ${geoSummary}
   - ${aliasMatchSummary}
${journalSummary}`;
  }).join("\n\n");

  const recentProjectList = ctx.contact.recent_projects.length > 0
    ? ctx.contact.recent_projects.map((p) => p.project_name).join(", ")
    : "None";

  const fanoutClass = ctx.contact.fanout_class || (ctx.contact.floater_flag ? "floater" : "unknown");
  const effectiveFanout = ctx.contact.effective_fanout ?? (ctx.contact.floater_flag ? 5 : 0);
  const fanoutSignal = fanoutClass === "anchored"
    ? "STRONG signal — contact works on only 1 project"
    : fanoutClass === "semi_anchored"
    ? "Moderate signal — contact works on 2 projects, needs corroboration"
    : fanoutClass === "drifter"
    ? "Weak signal — contact works on 3-4 projects, needs transcript grounding"
    : fanoutClass === "floater"
    ? "ANTI-signal — contact works on 5+ projects, treat like staff"
    : "No signal — no project association";

  const emailItems = Array.isArray(ctx.email_context) ? ctx.email_context.slice(0, 5) : [];
  const emailLookupMeta = ctx.email_lookup_meta || null;
  const emailLookupSummary = emailLookupMeta
    ? `returned=${Number(emailLookupMeta.returned_count || emailItems.length)}, cached=${
      emailLookupMeta.cached === true ? "yes" : "no"
    }, range=${emailLookupMeta.date_range || "unknown"}`
    : "not_run";
  const emailWarnings = emailLookupMeta?.warnings?.length ? emailLookupMeta.warnings.slice(0, 4).join(", ") : "none";
  const emailContextSummary = emailItems.length > 0
    ? emailItems.map((item, idx) => {
      const mentions = item.project_mentions?.length ? item.project_mentions.slice(0, 3).join(", ") : "none";
      const amounts = item.amounts_mentioned?.length ? item.amounts_mentioned.slice(0, 3).join(", ") : "none";
      const keywords = item.subject_keywords?.length ? item.subject_keywords.slice(0, 5).join(", ") : "none";
      const subject = (item.subject || "no subject").replace(/\s+/g, " ").slice(0, 120);
      const when = item.date || "unknown_date";
      return `${
        idx + 1
      }. ${when} | subject="${subject}" | mentions=[${mentions}] | amounts=[${amounts}] | keywords=[${keywords}]`;
    }).join("\n")
    : "No recent vendor email context";

  const placeMentions = Array.isArray(ctx.place_mentions) ? ctx.place_mentions.slice(0, 8) : [];
  const placeMentionSummary = placeMentions.length > 0
    ? placeMentions.map((p, idx) => {
      const roleTag = p.trigger_verb ? `${p.role} via "${p.trigger_verb}"` : `${p.role}`;
      const loc = (p.lat != null && p.lon != null) ? `${p.lat.toFixed(4)},${p.lon.toFixed(4)}` : "n/a";
      return `${idx + 1}. ${p.place_name} | role=${roleTag} | loc=${loc} | quote="${(p.snippet || "").slice(0, 90)}"`;
    }).join("\n")
    : "No explicit place mentions detected";

  return `TRANSCRIPT SEGMENT:
"""
${ctx.span.transcript_text}
"""

CALLER INFO:
- Name: ${ctx.contact.contact_name || "Unknown"}
- Fanout: ${effectiveFanout} projects (${fanoutClass})
- Signal strength: ${fanoutSignal}
- Recent Projects: ${recentProjectList}

EMAIL CONTEXT (WEAK CORROBORATION):
- Lookup: ${emailLookupSummary}
- Warnings: ${emailWarnings}
${emailContextSummary}

GEO PLACE MENTIONS (WEAK CORROBORATION):
${placeMentionSummary}

CANDIDATE PROJECTS (${ctx.candidates.length} total):
${candidateList || "No candidates found"}

Analyze the transcript and determine which project (if any) this conversation is about.
Consider the contact's fanout class — an anchored contact (fanout=1) on a single project is strong evidence; a floater (fanout>=5) provides no identity signal.
Consider the journal context for each project — if the conversation topic matches known commitments, decisions, or open loops for a project, that strengthens the attribution.
Treat email context as weak corroboration only; never use email context alone for decision="assign".
Treat geo context as weak corroboration only; use it as a tie-breaker when transcript evidence is otherwise close.
If journal claims influenced your decision, include them in journal_references.
Remember: You MUST include an exact quote from the transcript to use decision="assign".`;
}

// ============================================================
// MAIN HANDLER
// ============================================================

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const edgeSecretHeader = req.headers.get("X-Edge-Secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!expectedSecret || edgeSecretHeader !== expectedSecret) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  let context_package: ContextPackage | null = body.context_package || null;
  const dry_run = body.dry_run === true;
  const request_source = String(body.source || "").toLowerCase();

  if (!context_package) {
    return new Response(JSON.stringify({ error: "missing_context_package" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const span_id = context_package.meta?.span_id;
  if (!span_id) {
    return new Response(JSON.stringify({ error: "missing_span_id_in_context_package" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const candidateFilterResult = filterClosedProjectCandidates(context_package);
  context_package = candidateFilterResult.filtered;
  const contextStrongProjectIds = inferStrongProjectIdsFromCandidates(context_package.candidates || []);
  if (candidateFilterResult.removed_count > 0) {
    console.log(
      `[ai-router] Closed-project hard filter removed ${candidateFilterResult.removed_count} candidates pre-inference`,
    );
  }

  const homeownerOverrideStrongAnchor = homeownerOverrideActsAsStrongAnchor(context_package.meta);
  const interaction_id = context_package.meta?.interaction_id || null;
  const transcriptText = context_package.span?.transcript_text || "";

  const { data: spanMeta } = await db
    .from("conversation_spans")
    .select("span_index, transcript_segment, interaction_id")
    .eq("id", span_id)
    .maybeSingle();

  const span_index = Number(spanMeta?.span_index ?? context_package.meta?.span_index ?? -1);
  const resolvedInteractionId = interaction_id || spanMeta?.interaction_id || null;
  const span_chars = Math.max(
    transcriptText.length,
    String(spanMeta?.transcript_segment || "").length,
  );
  const priorAssignedProjectIds = await fetchPriorAssignedProjects(db, resolvedInteractionId, span_index);

  let result: AttributionResult;
  let raw_response: any = null;
  let tokens_used = 0;
  let inference_ms = 0;
  let model_error = false;
  let common_alias_unconfirmed = false;
  let common_alias_terms: string[] = [];
  let bizdev_call_type: "bizdev_prospect_intake" | "project_execution" = "project_execution";
  let bizdev_confidence: "high" | "medium" | "low" = "low";
  let bizdev_evidence_tags: string[] = [];
  let bizdev_commitment_to_start = false;
  let bizdev_commitment_tags: string[] = [];
  let bizdev_without_commitment = false;
  let adjacent_coherence_guardrail = false;
  let adjacent_coherence_reason: string | null = null;
  let closed_project_guardrail = false;

  try {
    const anthropic = new Anthropic({
      apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    });

    const inferenceStart = Date.now();

    const response = await anthropic.messages.create({
      model: MODEL_ID,
      max_tokens: MAX_TOKENS,
      messages: [
        { role: "user", content: buildUserPrompt(context_package) },
      ],
      system: SYSTEM_PROMPT,
    });

    inference_ms = Date.now() - inferenceStart;
    tokens_used = (response.usage?.input_tokens || 0) + (response.usage?.output_tokens || 0);
    raw_response = response;

    const textBlock = response.content.find((b: any) => b.type === "text");
    const responseText = textBlock?.type === "text" ? textBlock.text : "";

    const parsed = parseLlmJson<any>(responseText).value;

    let project_id = parsed.project_id || null;
    let confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
    const anchors: Anchor[] = Array.isArray(parsed.anchors) ? parsed.anchors : [];
    const suggested_aliases: SuggestedAlias[] = Array.isArray(parsed.suggested_aliases) ? parsed.suggested_aliases : [];
    const journal_references: JournalReference[] = Array.isArray(parsed.journal_references)
      ? parsed.journal_references
      : [];

    let decision = parsed.decision as "assign" | "review" | "none";
    let reasoning = parsed.reasoning || "No reasoning provided";
    const spanTranscript = context_package.span?.transcript_text || "";
    const { valid: hasValidAnchor, validatedAnchors, rejectedStaffAnchors } = validateAnchorQuotes(
      anchors,
      spanTranscript,
    );

    if (rejectedStaffAnchors > 0) {
      console.log(
        `[ai-router] Rejected ${rejectedStaffAnchors} staff-name anchors, ${validatedAnchors.length} valid anchors remain`,
      );
    }

    if (decision === "assign" && !hasValidAnchor) {
      decision = "review";
      console.log(
        `[ai-router] Downgraded to review: no valid anchors after filtering (staff anchors rejected: ${rejectedStaffAnchors})`,
      );
    }

    if (decision === "assign" && !hasStrongAnchor(validatedAnchors) && !homeownerOverrideStrongAnchor) {
      decision = "review";
      console.log(
        `[ai-router] Downgraded to review: only weak anchors (city/location), no strong anchor (project name, address, client)`,
      );
    } else if (decision === "assign" && !hasStrongAnchor(validatedAnchors) && homeownerOverrideStrongAnchor) {
      console.log(
        "[ai-router] Homeowner override active: preserving assign despite weak anchor set",
      );
    }

    const aliasGuardrail = applyCommonAliasCorroborationGuardrail({
      decision,
      project_id,
      anchors: validatedAnchors,
    });
    decision = aliasGuardrail.decision;
    common_alias_unconfirmed = aliasGuardrail.common_alias_unconfirmed;
    common_alias_terms = aliasGuardrail.flagged_alias_terms;
    if (aliasGuardrail.downgraded) {
      console.log(
        `[ai-router] Downgraded to review: common-word alias lacked corroboration for project ${project_id} (aliases=${
          common_alias_terms.join(",") || "unknown"
        })`,
      );
    }

    if (decision === "assign" && confidence < THRESHOLD_AUTO_ASSIGN) {
      decision = "review";
    }
    if (confidence < THRESHOLD_REVIEW) {
      decision = "none";
    }

    const bizdevGate = applyBizDevCommitmentGate({
      transcript: spanTranscript,
      decision,
      project_id,
    });
    decision = bizdevGate.decision;
    project_id = bizdevGate.project_id;
    bizdev_call_type = bizdevGate.classification.call_type;
    bizdev_confidence = bizdevGate.classification.confidence;
    bizdev_evidence_tags = bizdevGate.classification.evidence_tags;
    bizdev_commitment_to_start = bizdevGate.classification.commitment_to_start;
    bizdev_commitment_tags = bizdevGate.classification.commitment_tags;
    bizdev_without_commitment = bizdevGate.reason === "bizdev_without_commitment";

    if (bizdev_without_commitment) {
      const signalSummary = bizdev_evidence_tags.slice(0, 4).join(", ");
      const commitmentSummary = bizdev_commitment_tags.slice(0, 4).join(", ");
      reasoning = `${reasoning} BizDev prospect gate held project assignment (${
        signalSummary || "prospect signals detected"
      }; commitment_terms=${commitmentSummary || "none"}).`;
      console.log(
        `[ai-router] BizDev commitment gate active: project assignment withheld (signals=${signalSummary || "none"})`,
      );
    }

    const contextStrongProjectIdsForInvariant = span_chars > 2000 ? contextStrongProjectIds : [];
    const autoResegmentInvariant = evaluateAutoResegmentInvariant({
      span_chars,
      anchors: validatedAnchors.map((a) => ({
        match_type: a.match_type,
        candidate_project_id: a.candidate_project_id,
      })),
      additional_strong_project_ids: contextStrongProjectIdsForInvariant,
    });
    if (autoResegmentInvariant.triggered) {
      const invariantReason = autoResegmentInvariant.reasons.join(",");
      const reseedReason = `auto_resegment_invariant:${invariantReason}`;
      const reseedDispatch = (dry_run || request_source === "admin-reseed")
        ? {
          dispatched: false,
          status: null,
          detail: dry_run ? "dry_run" : "source_admin_reseed_skip_dispatch",
        }
        : await triggerAutoReseed({
          interaction_id: resolvedInteractionId,
          reason: reseedReason,
        });

      console.warn(
        `[ai-router] Auto-resegment invariant triggered for span ${span_id}: ${invariantReason} (dispatched=${reseedDispatch.dispatched})`,
      );

      return new Response(
        JSON.stringify({
          ok: false,
          error: "auto_resegment_required",
          error_code: "auto_resegment_required",
          span_id,
          interaction_id: resolvedInteractionId,
          span_index,
          invariant: autoResegmentInvariant,
          context_strong_project_ids: contextStrongProjectIdsForInvariant,
          reseed_dispatched: reseedDispatch.dispatched,
          reseed_status: reseedDispatch.status,
          reseed_detail: reseedDispatch.detail,
          dry_run,
          function_version: FUNCTION_VERSION,
          model_id: MODEL_ID,
          prompt_version: PROMPT_VERSION,
          tokens_used,
          inference_ms,
          ms: Date.now() - t0,
        }),
        {
          status: 409,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const coherence = evaluateAdjacentSpanCoherence({
      span_index,
      transcript_text: spanTranscript,
      current_project_id: project_id,
      prior_assigned_project_ids: priorAssignedProjectIds,
      candidate_project_ids: (context_package.candidates || []).map((c) => c.project_id),
    });
    adjacent_coherence_guardrail = coherence.enforced;
    adjacent_coherence_reason = coherence.reason;
    if (coherence.enforced) {
      if (coherence.override_project_id) {
        project_id = coherence.override_project_id;
        decision = "assign";
        confidence = Math.max(confidence, THRESHOLD_AUTO_ASSIGN);
        reasoning = `${reasoning} Adjacent-span coherence preserved prior project continuity (span ${span_index}).`;
      } else if (coherence.downgrade_to_review) {
        project_id = null;
        decision = "review";
        reasoning = `${reasoning} Adjacent-span coherence guard withheld project hop without switch signal.`;
      }
    }

    if (project_id) {
      const candidateRow = (context_package.candidates || []).find((c) => c.project_id === project_id);
      let projectEligible = candidateRow ? isAttributionEligibleProject(candidateRow.status) : false;
      if (!projectEligible) {
        const { data: projectRow } = await db
          .from("projects")
          .select("status, project_kind")
          .eq("id", project_id)
          .maybeSingle();
        projectEligible = !!projectRow && isAttributionEligibleProject(projectRow.status, projectRow.project_kind);
      }
      if (!projectEligible) {
        closed_project_guardrail = true;
        project_id = null;
        decision = "review";
        reasoning = `${reasoning} Closed-project hard filter withheld attribution for ineligible project status.`;
        console.log("[ai-router] Closed-project hard filter downgraded assignment candidate");
      }
    }

    result = {
      span_id,
      project_id,
      confidence,
      decision,
      reasoning,
      anchors: validatedAnchors,
      suggested_aliases: suggested_aliases.length > 0 ? suggested_aliases : undefined,
      journal_references: journal_references.length > 0 ? journal_references : undefined,
    };
  } catch (e: any) {
    console.error("AI Router inference error:", e.message);
    model_error = true;

    result = {
      span_id,
      project_id: null,
      confidence: 0,
      decision: "review",
      reasoning: `model_error: ${e.message}`,
      anchors: [],
    };
  }

  // ========================================
  // BLOCKLIST ENFORCEMENT (belt-and-suspenders)
  // ========================================
  if (result.project_id) {
    const { data: blockRow } = await db
      .from("project_attribution_blocklist")
      .select("block_mode, reason")
      .eq("project_id", result.project_id)
      .eq("active", true)
      .eq("block_mode", "hard_block")
      .maybeSingle();

    if (blockRow) {
      console.log(`[ai-router] BLOCKLIST HIT: project_id=${result.project_id} blocked (${blockRow.reason})`);
      result = {
        ...result,
        project_id: null,
        confidence: 0,
        decision: "none",
        reasoning: `blocked_project: ${blockRow.reason}. Original decision overridden by blocklist.`,
      };
    }
  }

  // ========================================
  // GATEKEEPER (SPAN-LEVEL ONLY)
  // ========================================
  let applied = false;
  let applied_project_id: string | null = null;
  let gatekeeper_reason: string | null = null;
  let journal_extract_fired = false;

  if (!dry_run) {
    const { data: existingAttribution } = await db
      .from("span_attributions")
      .select("attribution_lock")
      .eq("span_id", span_id)
      .maybeSingle();

    const currentLock = existingAttribution?.attribution_lock ?? null;

    const wouldApply = result.decision === "assign" && result.confidence >= THRESHOLD_AUTO_ASSIGN;
    const newLock = wouldApply ? "ai" : null;

    if (!canOverwriteLock(currentLock, newLock)) {
      gatekeeper_reason = currentLock === "human" ? "human_lock_present" : "ai_lock_preserved";
      applied = false;
      applied_project_id = null;
      console.log(`[ai-router] Lock preserved: current=${currentLock}, attempted=${newLock}`);
    } else {
      const spanTranscript = context_package.span?.transcript_text || "";
      const { valid: hasValidAnchor } = validateAnchorQuotes(result.anchors, spanTranscript);

      if (result.decision === "assign" && result.confidence >= THRESHOLD_AUTO_ASSIGN && hasValidAnchor) {
        applied = true;
        applied_project_id = result.project_id;
        gatekeeper_reason = "auto_assigned";
      } else if (
        result.decision === "review" ||
        (result.confidence >= THRESHOLD_REVIEW && result.confidence < THRESHOLD_AUTO_ASSIGN)
      ) {
        applied = false;
        applied_project_id = null;
        gatekeeper_reason = "needs_review";
      } else {
        applied = false;
        applied_project_id = null;
        gatekeeper_reason = "no_match";
      }
    }

    // ========================================
    // WRITE TO SPAN_ATTRIBUTIONS (ALWAYS)
    // ========================================
    const attribution_lock = applied ? "ai" : null;
    const needs_review = result.decision === "review" || result.decision === "none";
    const attribution_source = deriveAttributionSource(result.anchors, model_error);
    const evidence_tier = deriveEvidenceTier(result.anchors, result.confidence, model_error);

    const { error: upsertErr } = await db.from("span_attributions").upsert({
      span_id,
      project_id: result.project_id,
      confidence: result.confidence,
      decision: result.decision,
      reasoning: result.reasoning,
      anchors: result.anchors,
      journal_references: result.journal_references || [],
      suggested_aliases: result.suggested_aliases || [],
      prompt_version: PROMPT_VERSION,
      model_id: MODEL_ID,
      raw_response,
      tokens_used,
      inference_ms,
      attribution_lock,
      applied_project_id,
      applied_at_utc: applied ? new Date().toISOString() : null,
      needs_review,
      attribution_source,
      evidence_tier,
      attributed_by: `ai-router-${FUNCTION_VERSION}`,
      attributed_at: new Date().toISOString(),
    }, {
      onConflict: "span_id,model_id,prompt_version",
      ignoreDuplicates: false,
    });

    if (upsertErr) {
      console.error("[ai-router] span_attributions upsert failed:", upsertErr.message, upsertErr.details);
    }

    // ========================================
    // REVIEW QUEUE WIRING (PR-4)
    // ========================================
    const interaction_id = context_package.meta?.interaction_id;
    const quoteVerified = result.anchors.length > 0;
    const strongAnchorPresent = hasStrongAnchor(result.anchors);
    const effectiveStrongAnchor = strongAnchorPresent || homeownerOverrideStrongAnchor;

    const needsReviewQueue = result.decision !== "assign" ||
      needs_review === true ||
      !quoteVerified ||
      !effectiveStrongAnchor ||
      common_alias_unconfirmed ||
      bizdev_without_commitment ||
      adjacent_coherence_guardrail ||
      closed_project_guardrail ||
      model_error;

    if (needsReviewQueue) {
      const reason_codes = buildReasonCodes({
        modelReasons: null,
        quoteVerified,
        strongAnchor: effectiveStrongAnchor,
        modelError: model_error,
        ambiguousContact: (context_package.contact?.fanout_class === "floater" ||
          context_package.contact?.fanout_class === "drifter") || (context_package.contact?.floater_flag === true),
        geoOnly: !effectiveStrongAnchor && result.anchors.some((a) => a.match_type === "city_or_location"),
        commonAliasUnconfirmed: common_alias_unconfirmed,
        bizdevWithoutCommitment: bizdev_without_commitment,
        coherenceGuardrail: adjacent_coherence_guardrail,
        closedProjectGuardrail: closed_project_guardrail,
      });

      const context_payload = {
        span_id,
        interaction_id,
        transcript_snippet: (context_package.span?.transcript_text || "").slice(0, 600),
        candidates: context_package.candidates?.map((c) => ({
          project_id: c.project_id,
          name: c.project_name,
          evidence_tags: c.evidence?.sources || [],
        })) || [],
        anchors: result.anchors,
        alias_guardrails: {
          common_alias_unconfirmed,
          flagged_alias_terms: common_alias_terms,
        },
        bizdev_classifier: {
          call_type: bizdev_call_type,
          confidence: bizdev_confidence,
          evidence_tags: bizdev_evidence_tags,
          commitment_to_start: bizdev_commitment_to_start,
          commitment_tags: bizdev_commitment_tags,
          gate_active: bizdev_without_commitment,
        },
        homeowner_override: {
          active: homeownerOverrideStrongAnchor,
          project_id: context_package.meta?.homeowner_override_project_id || null,
          conflict_project_id: context_package.meta?.homeowner_override_conflict_project_id || null,
          conflict_term: context_package.meta?.homeowner_override_conflict_term || null,
        },
        coherence_guardrail: {
          active: adjacent_coherence_guardrail,
          reason: adjacent_coherence_reason,
          span_index,
          prior_assigned_project_ids: priorAssignedProjectIds,
        },
        closed_project_guardrail: {
          active: closed_project_guardrail,
        },
        model_id: MODEL_ID,
        prompt_version: PROMPT_VERSION,
        created_at_utc: new Date().toISOString(),
      };

      await upsertReviewQueue(db, {
        span_id,
        interaction_id: interaction_id || span_id,
        reasons: reason_codes,
        context_payload,
      });
      console.log(`[ai-router] Created review_queue item for span ${span_id}, reasons: ${reason_codes.join(",")}`);
    } else {
      await resolveReviewQueue(db, span_id, "auto-applied by ai-router");
      console.log(`[ai-router] Resolved review_queue item for span ${span_id} (auto-assigned)`);
    }

    // ========================================
    // v1.8.1: CHAIN TO JOURNAL-EXTRACT (fire-and-forget)
    // Fires after attribution lands so journal-extract can read
    // applied_project_id from span_attributions.
    // Belt-and-suspenders with segment-call hook — ensures journal
    // extraction runs even for backfill/replay/manual invocations.
    // journal-extract has its own idempotency guard (skips if claims
    // already exist for this span_id) and handles null project_id
    // gracefully (skips DB insert, returns reason).
    // ========================================
    if (!model_error && span_id) {
      const edgeSecretVal = Deno.env.get("EDGE_SHARED_SECRET");
      const journalExtractUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/journal-extract`;
      if (edgeSecretVal) {
        try {
          const jeResp = await fetch(journalExtractUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Edge-Secret": edgeSecretVal,
            },
            body: JSON.stringify({
              span_id,
              interaction_id: context_package.meta?.interaction_id,
            }),
          });
          journal_extract_fired = true;
          if (!jeResp.ok) {
            const errBody = await jeResp.text().catch(() => "unknown");
            console.warn(`[ai-router] journal-extract chain ${jeResp.status}: ${errBody.slice(0, 200)}`);
          } else {
            const jeData = await jeResp.json().catch(() => null);
            console.log(
              `[ai-router] journal-extract chain OK: claims_extracted=${
                jeData?.claims_extracted ?? "?"
              }, claims_written=${jeData?.claims_written ?? "?"}`,
            );
          }
        } catch (e: any) {
          console.warn(`[ai-router] journal-extract chain error: ${e.message}`);
        }
      }
    }
  }

  // ========================================
  // RESPONSE
  // ========================================
  return new Response(
    JSON.stringify({
      ok: true,
      span_id,
      project_id: result.project_id,
      confidence: result.confidence,
      decision: result.decision,
      reasoning: result.reasoning,
      anchors: result.anchors,
      journal_references: result.journal_references,
      suggested_aliases: result.suggested_aliases,
      gatekeeper: {
        applied,
        applied_project_id,
        reason: gatekeeper_reason,
      },
      guardrails: {
        common_alias_unconfirmed,
        flagged_alias_terms: common_alias_terms,
        adjacent_coherence: {
          active: adjacent_coherence_guardrail,
          reason: adjacent_coherence_reason,
          span_index,
          prior_assigned_project_ids: priorAssignedProjectIds,
        },
        closed_project_filter: {
          active: closed_project_guardrail,
          pre_inference_candidates_removed: candidateFilterResult.removed_count,
        },
        bizdev_classifier: {
          call_type: bizdev_call_type,
          confidence: bizdev_confidence,
          evidence_tags: bizdev_evidence_tags,
          commitment_to_start: bizdev_commitment_to_start,
          commitment_tags: bizdev_commitment_tags,
          gate_active: bizdev_without_commitment,
        },
      },
      post_hooks: {
        journal_extract_fired,
      },
      model_error,
      dry_run,
      model_id: MODEL_ID,
      prompt_version: PROMPT_VERSION,
      function_version: FUNCTION_VERSION,
      tokens_used,
      inference_ms,
      ms: Date.now() - t0,
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    },
  );
});
