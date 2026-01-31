/**
 * ai-router Edge Function v1.0.1
 * LLM-based project attribution for conversation spans
 *
 * @version 1.0.1
 * @date 2026-01-31
 * @purpose Use Claude Haiku to attribute spans to projects with anchored evidence
 *
 * CORE PRINCIPLE: span_attributions is the single source of truth.
 * NO writes to interactions.project_id from this path.
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

const PROMPT_VERSION = "v1.5.0";
const MODEL_ID = "claude-3-haiku-20240307";
const MAX_TOKENS = 1024;

// Confidence thresholds
const THRESHOLD_AUTO_ASSIGN = 0.75;
const THRESHOLD_REVIEW = 0.50;

// ============================================================
// TYPES
// ============================================================

interface Anchor {
  text: string;
  candidate_project_id: string | null;
  match_type: string;
  quote: string;
}

interface SuggestedAlias {
  project_id: string;
  alias_term: string;
  rationale: string;
}

interface AttributionResult {
  span_id: string;
  project_id: string | null;
  confidence: number;
  decision: "assign" | "review" | "none";
  reasoning: string;
  anchors: Anchor[];
  suggested_aliases?: SuggestedAlias[];
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
      assigned: boolean;
      alias_matches: Array<{ term: string; match_type: string; snippet?: string }>;
    };
  }>;
}

// ============================================================
// GUARDRAIL HELPERS
// ============================================================

// HCB staff names - these are NOT project evidence
// Used for programmatic filtering of invalid anchors
const HCB_STAFF_PATTERNS = [
  "zack sittler",
  "zachary sittler",
  "zach sittler",
  "chad barlow",
  "sittler:", // Speaker label pattern
];

/**
 * Check if an anchor quote contains HCB staff names (invalid evidence)
 */
function anchorContainsStaffName(quote: string): boolean {
  const quoteLower = (quote || "").toLowerCase();
  // Check if quote is primarily about a staff name
  for (const pattern of HCB_STAFF_PATTERNS) {
    if (quoteLower.includes(pattern)) {
      return true;
    }
  }
  // Also check if quote is just "Sittler" alone (not part of a project name like "Sittler Residence")
  if (/\bsittler\b/i.test(quote) && !/residence|project|house/i.test(quote)) {
    return true;
  }
  return false;
}

/**
 * Validates that at least one anchor quote actually appears in the transcript.
 * Also filters out anchors that use HCB staff names as evidence.
 * Normalizes both strings (lowercase, collapse whitespace) for fuzzy matching.
 */
function validateAnchorQuotes(
  anchors: Anchor[],
  transcript: string,
): { valid: boolean; validatedAnchors: Anchor[]; rejectedStaffAnchors: number } {
  if (!transcript || !anchors.length) {
    return { valid: false, validatedAnchors: [], rejectedStaffAnchors: 0 };
  }

  // Normalize: lowercase, collapse whitespace, trim
  const normalizeText = (s: string) => (s || "").toLowerCase().replace(/\s+/g, " ").trim();
  const transcriptNorm = normalizeText(transcript);

  const validatedAnchors: Anchor[] = [];
  let rejectedStaffAnchors = 0;

  for (const anchor of anchors) {
    if (!anchor.quote || anchor.quote.length === 0) continue;

    const quoteNorm = normalizeText(anchor.quote);
    if (quoteNorm.length < 3) continue; // Too short to be meaningful

    // HARD FILTER: Reject anchors that use staff names as evidence
    if (anchorContainsStaffName(anchor.quote) || anchorContainsStaffName(anchor.text || "")) {
      rejectedStaffAnchors++;
      console.log(`[ai-router] Rejected staff-name anchor: "${anchor.quote}"`);
      continue;
    }

    // Check if quote appears in transcript
    if (!transcriptNorm.includes(quoteNorm)) {
      console.log(`[ai-router] Rejected anchor: quote not in transcript: "${anchor.quote}"`);
      continue;
    }

    // COHERENCE CHECK: anchor.text must appear in anchor.quote
    // Prevents model from claiming text="Athens" with quote="i'm in bostwick"
    const textNorm = normalizeText(anchor.text || "");
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

// Anchor strength classification
// STRONG anchors can support auto-assign; WEAK anchors force REVIEW
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

/**
 * Check if anchors contain at least one STRONG anchor type.
 * City/zip/county alone is insufficient for auto-assign.
 */
function hasStrongAnchor(anchors: Anchor[]): boolean {
  return anchors.some((a) => STRONG_ANCHOR_TYPES.includes(a.match_type));
}

/**
 * Lock ordering: human > ai > null
 * Returns true if newLock can overwrite currentLock
 */
function canOverwriteLock(currentLock: string | null, newLock: string | null): boolean {
  const lockOrder: Record<string, number> = { "human": 3, "ai": 2 };
  const currentLevel = lockOrder[currentLock || ""] || 0;
  const newLevel = lockOrder[newLock || ""] || 0;

  // Can only overwrite if new level >= current level
  // This means: ai can overwrite ai or null, but not human
  // null cannot overwrite ai or human
  return newLevel >= currentLevel;
}

// ============================================================
// REVIEW QUEUE HELPERS (PR-4)
// ============================================================

/**
 * Build reason_codes array for review_queue
 * Combines model reasons + system-detected conditions
 */
function buildReasonCodes(opts: {
  modelReasons?: string[] | null;
  quoteVerified: boolean;
  strongAnchor: boolean;
  modelError?: boolean;
  ambiguousContact?: boolean;
  geoOnly?: boolean;
}): string[] {
  const reasons: string[] = [];
  if (Array.isArray(opts.modelReasons)) reasons.push(...opts.modelReasons);

  if (!opts.quoteVerified) reasons.push("quote_unverified");
  if (!opts.strongAnchor) reasons.push("weak_anchor");
  if (opts.ambiguousContact) reasons.push("ambiguous_contact");
  if (opts.geoOnly) reasons.push("geo_only");
  if (opts.modelError) reasons.push("model_error");

  // Dedupe
  return Array.from(new Set(reasons.filter(Boolean)));
}

/**
 * Upsert a review item keyed by span_id
 * Uses existing review_queue schema (reasons, pending/resolved/dismissed)
 * Writes BOTH reason_codes AND reasons for back-compat (reconciled PR-4)
 */
async function upsertReviewQueue(
  db: ReturnType<typeof createClient>,
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
        reason_codes: payload.reasons, // New column (preferred)
        reasons: payload.reasons, // Legacy column (back-compat)
        context_payload: payload.context_payload,
      },
      { onConflict: "span_id" },
    );

  if (error) {
    console.error("[ai-router] review_queue upsert failed:", error.message);
  }
}

/**
 * Resolve any open review item for a span (when auto-assign succeeds)
 */
async function resolveReviewQueue(
  db: ReturnType<typeof createClient>,
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
3. If the contact is a "floater" (works across many projects), assignment is NOT reliable - prioritize transcript anchors
4. If multiple projects are mentioned, choose the PRIMARY topic of discussion
5. If uncertain, choose "review" with confidence 0.50-0.74
6. If no clear project match exists in the transcript, choose "none" with confidence <0.50

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
  const candidateList = ctx.candidates.map((c, i) => {
    const aliasMatchSummary = c.evidence.alias_matches.length > 0
      ? `Matches in transcript: ${c.evidence.alias_matches.map((m) => `"${m.term}" (${m.match_type})`).join(", ")}`
      : "No direct transcript matches";

    return `${i + 1}. ${c.project_name}
   - ID: ${c.project_id}
   - Address: ${c.address || "N/A"}
   - Client: ${c.client_name || "N/A"}
   - Aliases: ${c.aliases.length > 0 ? c.aliases.slice(0, 5).join(", ") : "None"}
   - Status: ${c.status || "N/A"}, Phase: ${c.phase || "N/A"}
   - Evidence: assigned=${c.evidence.assigned}, affinity=${c.evidence.affinity_weight.toFixed(2)}, sources=[${
      c.evidence.sources.join(",")
    }]
   - ${aliasMatchSummary}`;
  }).join("\n\n");

  const recentProjectList = ctx.contact.recent_projects.length > 0
    ? ctx.contact.recent_projects.map((p) => p.project_name).join(", ")
    : "None";

  return `TRANSCRIPT SEGMENT:
"""
${ctx.span.transcript_text}
"""

CALLER INFO:
- Name: ${ctx.contact.contact_name || "Unknown"}
- Is Floater (works across many projects): ${ctx.contact.floater_flag}
- Recent Projects: ${recentProjectList}

CANDIDATE PROJECTS (${ctx.candidates.length} total):
${candidateList || "No candidates found"}

Analyze the transcript and determine which project (if any) this conversation is about.
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

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const context_package: ContextPackage | null = body.context_package || null;
  const dry_run = body.dry_run === true;

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

  let result: AttributionResult;
  let raw_response: any = null;
  let tokens_used = 0;
  let inference_ms = 0;
  let model_error = false;

  try {
    // ========================================
    // CALL CLAUDE HAIKU
    // ========================================
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

    // Parse response
    const textBlock = response.content.find((b) => b.type === "text");
    const responseText = textBlock?.type === "text" ? textBlock.text : "";

    // Extract JSON from response (handle potential markdown wrapping)
    let jsonStr = responseText;
    const jsonMatch = responseText.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      jsonStr = jsonMatch[0];
    }

    const parsed = JSON.parse(jsonStr);

    // Validate and build result
    const project_id = parsed.project_id || null;
    const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
    const anchors: Anchor[] = Array.isArray(parsed.anchors) ? parsed.anchors : [];
    const suggested_aliases: SuggestedAlias[] = Array.isArray(parsed.suggested_aliases) ? parsed.suggested_aliases : [];

    // HARD GUARDRAIL: decision="assign" requires transcript-grounded anchor
    // Quote must ACTUALLY APPEAR in the transcript (substring match)
    // Staff-name anchors are filtered out programmatically
    let decision = parsed.decision as "assign" | "review" | "none";
    const spanTranscript = context_package.span?.transcript_text || "";
    const { valid: hasValidAnchor, validatedAnchors, rejectedStaffAnchors } = validateAnchorQuotes(
      anchors,
      spanTranscript,
    );

    // Log if staff anchors were rejected
    if (rejectedStaffAnchors > 0) {
      console.log(
        `[ai-router] Rejected ${rejectedStaffAnchors} staff-name anchors, ${validatedAnchors.length} valid anchors remain`,
      );
    }

    if (decision === "assign" && !hasValidAnchor) {
      // Downgrade to review if no valid anchor remains after filtering
      decision = "review";
      console.log(
        `[ai-router] Downgraded to review: no valid anchors after filtering (staff anchors rejected: ${rejectedStaffAnchors})`,
      );
    }

    // POLICY: Weak anchors (city/zip/county) alone cannot support auto-assign
    // Requires at least one STRONG anchor type (project name, address, client name)
    if (decision === "assign" && !hasStrongAnchor(validatedAnchors)) {
      decision = "review";
      console.log(
        `[ai-router] Downgraded to review: only weak anchors (city/location), no strong anchor (project name, address, client)`,
      );
    }

    // Apply confidence thresholds
    if (decision === "assign" && confidence < THRESHOLD_AUTO_ASSIGN) {
      decision = "review";
    }
    if (confidence < THRESHOLD_REVIEW) {
      decision = "none";
    }

    // USE VALIDATED ANCHORS (staff names filtered out)
    result = {
      span_id,
      project_id,
      confidence,
      decision,
      reasoning: parsed.reasoning || "No reasoning provided",
      anchors: validatedAnchors, // Use filtered anchors, not original
      suggested_aliases: suggested_aliases.length > 0 ? suggested_aliases : undefined,
    };
  } catch (e: any) {
    console.error("AI Router inference error:", e.message);
    model_error = true;

    // On model failure, still produce a result (decision=review)
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
  // GATEKEEPER (SPAN-LEVEL ONLY)
  // ========================================
  let applied = false;
  let applied_project_id: string | null = null;
  let gatekeeper_reason: string | null = null;

  if (!dry_run) {
    // Check existing span lock (handle "no row" case with maybeSingle)
    const { data: existingAttribution } = await db
      .from("span_attributions")
      .select("attribution_lock")
      .eq("span_id", span_id)
      .maybeSingle();

    const currentLock = existingAttribution?.attribution_lock ?? null;

    // Determine what lock we would write
    const wouldApply = result.decision === "assign" && result.confidence >= THRESHOLD_AUTO_ASSIGN;
    const newLock = wouldApply ? "ai" : null;

    // LOCK MONOTONICITY: human > ai > null
    // AI cannot overwrite human lock, and null cannot overwrite ai lock
    if (!canOverwriteLock(currentLock, newLock)) {
      gatekeeper_reason = currentLock === "human" ? "human_lock_present" : "ai_lock_preserved";
      applied = false;
      applied_project_id = null;
      console.log(`[ai-router] Lock preserved: current=${currentLock}, attempted=${newLock}`);
    } else {
      // Validate anchor quotes actually appear in transcript
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
    // Upsert on idempotency key: span_id + model_id + prompt_version
    const attribution_lock = applied ? "ai" : null;
    const needs_review = result.decision === "review" || result.decision === "none";

    const { error: upsertErr } = await db.from("span_attributions").upsert({
      span_id,
      project_id: result.project_id, // Model's predicted project
      confidence: result.confidence,
      decision: result.decision,
      reasoning: result.reasoning,
      anchors: result.anchors,
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
      attributed_by: `ai-router-${PROMPT_VERSION}`,
      attributed_at: new Date().toISOString(),
    }, {
      onConflict: "span_id,model_id,prompt_version",
      ignoreDuplicates: false,
    });

    if (upsertErr) {
      console.error("[ai-router] span_attributions upsert failed:", upsertErr.message, upsertErr.details);
      // Continue - we still return the result but log the error
    }

    // ========================================
    // REVIEW QUEUE WIRING (PR-4)
    // ========================================
    const interaction_id = context_package.meta?.interaction_id;
    const quoteVerified = result.anchors.length > 0;
    const strongAnchorPresent = hasStrongAnchor(result.anchors);

    const needsReviewQueue = result.decision !== "assign" ||
      needs_review === true ||
      !quoteVerified ||
      !strongAnchorPresent ||
      model_error;

    if (needsReviewQueue) {
      // Create/update review item for human triage
      const reason_codes = buildReasonCodes({
        modelReasons: null, // Model doesn't return these yet
        quoteVerified,
        strongAnchor: strongAnchorPresent,
        modelError: model_error,
        ambiguousContact: context_package.contact?.floater_flag === true,
        geoOnly: !strongAnchorPresent && result.anchors.some((a) => a.match_type === "city_or_location"),
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
        model_id: MODEL_ID,
        prompt_version: PROMPT_VERSION,
        created_at_utc: new Date().toISOString(),
      };

      await upsertReviewQueue(db, {
        span_id,
        interaction_id: interaction_id || span_id, // Fallback to span_id if no interaction_id
        reasons: reason_codes,
        context_payload,
      });
      console.log(`[ai-router] Created review_queue item for span ${span_id}, reasons: ${reason_codes.join(",")}`);
    } else {
      // Auto-assigned: close any stale open review item for this span
      await resolveReviewQueue(db, span_id, "auto-applied by ai-router");
      console.log(`[ai-router] Resolved review_queue item for span ${span_id} (auto-assigned)`);
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
      suggested_aliases: result.suggested_aliases,
      gatekeeper: {
        applied,
        applied_project_id,
        reason: gatekeeper_reason,
      },
      model_error,
      dry_run,
      model_id: MODEL_ID,
      prompt_version: PROMPT_VERSION,
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
