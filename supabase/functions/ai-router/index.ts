/**
 * ai-router Edge Function v2.0.0
 * LLM-based project attribution for conversation spans
 *
 * @version 2.0.0
 * @date 2026-02-08
 * @purpose Parallel OpenAI+Anthropic cascade for project attribution
 *
 * CORE PRINCIPLE: span_attributions is the single source of truth.
 * NO writes to interactions.project_id from this path.
 *
 * CASCADE DESIGN:
 *   - Each stage runs OpenAI(model_i) + Anthropic(model_i) in parallel
 *   - Agreement: both agree on same project_id + decision=assign => accept
 *   - Disagreement => escalate to next stage
 *   - Final stage disagreement => decision=review (fail closed)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROMPT_VERSION = "v2.0.0";
const MAX_TOKENS = 1024;
const DEFAULT_CASCADE_STAGE_TIMEOUT_MS = 12000;
const DEFAULT_AI_ROUTER_OPENAI_MODELS = ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"];
const DEFAULT_AI_ROUTER_ANTHROPIC_MODELS = [
  "claude-3-haiku-20240307",
  "claude-3-5-haiku-20241022",
  "claude-3-5-sonnet-20241022",
  "claude-3-7-sonnet-20250219",
];

const THRESHOLD_AUTO_ASSIGN = 0.75;
const THRESHOLD_REVIEW = 0.50;

type Provider = "openai" | "anthropic";
interface Anchor { text: string; candidate_project_id: string | null; match_type: string; quote: string; }
interface SuggestedAlias { project_id: string; alias_term: string; rationale: string; }
interface AttributionResult { span_id: string; project_id: string | null; confidence: number; decision: "assign" | "review" | "none"; reasoning: string; anchors: Anchor[]; suggested_aliases?: SuggestedAlias[]; }
interface ProviderCallResult { ok: boolean; provider: Provider; model: string; ms: number; project_id?: string | null; confidence?: number; decision?: "assign" | "review" | "none"; reasoning?: string; anchors?: Anchor[]; suggested_aliases?: SuggestedAlias[]; tokens_used?: number; error_code?: string; error_class?: string; raw_response?: any; }
interface CascadeCandidate { provider: Provider; model: string; stage: number; project_id: string | null; confidence: number; decision: "assign" | "review" | "none"; reasoning: string; anchors: Anchor[]; suggested_aliases?: SuggestedAlias[]; tokens_used: number; raw_response: any; }

interface ContextPackage {
  meta: { span_id: string; interaction_id: string; [key: string]: any };
  span: { transcript_text: string; [key: string]: any };
  contact: { contact_id: string | null; contact_name: string | null; floater_flag: boolean; recent_projects: Array<{ project_id: string; project_name: string }>; };
  candidates: Array<{ project_id: string; project_name: string; address: string | null; client_name: string | null; aliases: string[]; status: string | null; phase: string | null; evidence: { sources: string[]; affinity_weight: number; assigned: boolean; alias_matches: Array<{ term: string; match_type: string; snippet?: string }>; }; }>;
}

function parseModelList(envKey: string, defaults: string[]): string[] {
  const raw = Deno.env.get(envKey);
  if (!raw) return defaults;
  const parsed = raw.split(",").map((m) => m.trim()).filter(Boolean);
  return parsed.length > 0 ? parsed : defaults;
}

function parsePositiveIntEnv(envKey: string, defaultValue: number): number {
  const raw = Deno.env.get(envKey);
  if (!raw) return defaultValue;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : defaultValue;
}

function stripCodeFences(raw: string): string {
  return (raw || "").replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  let timeoutHandle: number | undefined;
  const timeoutPromise = new Promise<T>((_, reject) => {
    timeoutHandle = setTimeout(() => reject(new Error(`${label}_timeout`)), timeoutMs);
  });
  try { return await Promise.race([promise, timeoutPromise]); } finally { if (timeoutHandle !== undefined) clearTimeout(timeoutHandle); }
}

function parseAttributionJson(raw: string) {
  const cleaned = stripCodeFences(raw);
  const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
  const jsonStr = jsonMatch ? jsonMatch[0] : cleaned;
  const parsed = JSON.parse(jsonStr);
  return {
    project_id: parsed.project_id || null,
    confidence: Math.max(0, Math.min(1, Number(parsed.confidence) || 0)),
    decision: (["assign", "review", "none"].includes(parsed.decision) ? parsed.decision : "review") as "assign" | "review" | "none",
    reasoning: parsed.reasoning || "No reasoning provided",
    anchors: Array.isArray(parsed.anchors) ? parsed.anchors : [] as Anchor[],
    suggested_aliases: Array.isArray(parsed.suggested_aliases) ? parsed.suggested_aliases : [] as SuggestedAlias[],
  };
}

// GUARDRAILS
const HCB_STAFF_PATTERNS = ["zack sittler", "zachary sittler", "zach sittler", "chad barlow", "sittler:"];

function anchorContainsStaffName(quote: string): boolean {
  const quoteLower = (quote || "").toLowerCase();
  for (const pattern of HCB_STAFF_PATTERNS) { if (quoteLower.includes(pattern)) return true; }
  if (/\bsittler\b/i.test(quote) && !/residence|project|house/i.test(quote)) return true;
  return false;
}

function validateAnchorQuotes(anchors: Anchor[], transcript: string): { valid: boolean; validatedAnchors: Anchor[]; rejectedStaffAnchors: number } {
  if (!transcript || !anchors.length) return { valid: false, validatedAnchors: [], rejectedStaffAnchors: 0 };
  const normalizeText = (s: string) => (s || "").toLowerCase().replace(/\s+/g, " ").trim();
  const transcriptNorm = normalizeText(transcript);
  const validatedAnchors: Anchor[] = [];
  let rejectedStaffAnchors = 0;
  for (const anchor of anchors) {
    if (!anchor.quote || anchor.quote.length === 0) continue;
    const quoteNorm = normalizeText(anchor.quote);
    if (quoteNorm.length < 3) continue;
    if (anchorContainsStaffName(anchor.quote) || anchorContainsStaffName(anchor.text || "")) { rejectedStaffAnchors++; console.log(`[ai-router] Rejected staff-name anchor: "${anchor.quote}"`); continue; }
    if (!transcriptNorm.includes(quoteNorm)) { console.log(`[ai-router] Rejected anchor: quote not in transcript: "${anchor.quote}"`); continue; }
    const textNorm = normalizeText(anchor.text || "");
    if (textNorm.length >= 3 && !quoteNorm.includes(textNorm)) { console.log(`[ai-router] Rejected anchor: text "${anchor.text}" not found in quote "${anchor.quote}"`); continue; }
    validatedAnchors.push(anchor);
  }
  return { valid: validatedAnchors.length > 0, validatedAnchors, rejectedStaffAnchors };
}

const STRONG_ANCHOR_TYPES = ["exact_project_name", "alias", "address_fragment", "client_name"];
function hasStrongAnchor(anchors: Anchor[]): boolean { return anchors.some((a) => STRONG_ANCHOR_TYPES.includes(a.match_type)); }
function canOverwriteLock(currentLock: string | null, newLock: string | null): boolean { const lockOrder: Record<string, number> = { human: 3, ai: 2 }; return (lockOrder[newLock || ""] || 0) >= (lockOrder[currentLock || ""] || 0); }

function buildReasonCodes(opts: { modelReasons?: string[] | null; quoteVerified: boolean; strongAnchor: boolean; modelError?: boolean; ambiguousContact?: boolean; geoOnly?: boolean; modelDisagreement?: boolean }): string[] {
  const reasons: string[] = [];
  if (Array.isArray(opts.modelReasons)) reasons.push(...opts.modelReasons);
  if (!opts.quoteVerified) reasons.push("quote_unverified");
  if (!opts.strongAnchor) reasons.push("weak_anchor");
  if (opts.ambiguousContact) reasons.push("ambiguous_contact");
  if (opts.geoOnly) reasons.push("geo_only");
  if (opts.modelError) reasons.push("model_error");
  if (opts.modelDisagreement) reasons.push("model_disagreement");
  return Array.from(new Set(reasons.filter(Boolean)));
}

async function upsertReviewQueue(db: any, payload: { span_id: string; interaction_id: string; reasons: string[]; context_payload: Record<string, unknown> }) {
  const { error } = await db.from("review_queue").upsert({ span_id: payload.span_id, interaction_id: payload.interaction_id, status: "pending", reason_codes: payload.reasons, reasons: payload.reasons, context_payload: payload.context_payload }, { onConflict: "span_id" });
  if (error) console.error("[ai-router] review_queue upsert failed:", error.message);
}

async function resolveReviewQueue(db: any, spanId: string, notes: string) {
  const { error } = await db.from("review_queue").update({ status: "resolved", resolved_at: new Date().toISOString(), resolved_by: "ai-router", resolution_action: "confirmed", resolution_notes: notes }).eq("span_id", spanId).eq("status", "pending");
  if (error) console.error("[ai-router] review_queue resolve failed:", error.message);
}

// PROMPT
const SYSTEM_PROMPT = `You are a project attribution specialist for HCB (Heartwood Custom Builders), a Georgia construction company.
Given a phone call transcript segment and candidate projects, determine which project (if any) the conversation is about.

CRITICAL - HCB STAFF EXCLUSION (HIGHEST PRIORITY):
The following are HCB STAFF/OWNERS who appear on MANY calls. They are NOT project clients:
- "Zack Sittler", "Zachary Sittler", "Zach Sittler" (owner/general contractor)
- "Chad Barlow" (owner)
- The word "Sittler" alone, when it refers to Zack

STRICT RULES FOR STAFF NAMES:
1. NEVER use any HCB staff name as an anchor quote
2. NEVER match staff names to similarly-named projects
3. If the ONLY evidence for a project is a staff name match, output decision="review" or decision="none"
4. Speaker labels like "Zachary Sittler:" are NOT project evidence

RULES:
1. Look for explicit mentions of project names, addresses, CLIENT names (not staff), or known aliases
2. Caller's project assignments and call history are SECONDARY signals
3. If the contact is a "floater", assignment is NOT reliable - prioritize transcript anchors
4. If multiple projects are mentioned, choose the PRIMARY topic
5. If uncertain, choose "review" with confidence 0.50-0.74
6. If no clear project match, choose "none" with confidence <0.50

ANCHOR STRENGTH POLICY:
- STRONG: exact_project_name, alias, address_fragment, client_name
- WEAK: city_or_location, mentioned_contact, phonetic_or_pronunciation, continuity_callback, other
Weak anchors alone CANNOT support auto-assign.

CRITICAL GUARDRAIL:
To output decision="assign", you MUST provide at least one anchor with an EXACT QUOTE from the transcript.

OUTPUT FORMAT (JSON only, no markdown):
{"project_id":"<uuid or null>","confidence":0.00-1.00,"decision":"assign|review|none","reasoning":"<1-3 sentences>","anchors":[{"text":"<matched term>","candidate_project_id":"<uuid>","match_type":"<type>","quote":"<EXACT quote, max 50 chars>"}],"suggested_aliases":[{"project_id":"<uuid>","alias_term":"<term>","rationale":"<why>"}]}

IMPORTANT: The "quote" field must contain text that ACTUALLY APPEARS in the transcript.`;

function buildUserPrompt(ctx: ContextPackage): string {
  const candidateList = ctx.candidates.map((c, i) => {
    const aliasMatchSummary = c.evidence.alias_matches.length > 0 ? `Matches: ${c.evidence.alias_matches.map((m) => `"${m.term}" (${m.match_type})`).join(", ")}` : "No direct transcript matches";
    return `${i + 1}. ${c.project_name}\n   - ID: ${c.project_id}\n   - Address: ${c.address || "N/A"}\n   - Client: ${c.client_name || "N/A"}\n   - Aliases: ${c.aliases.length > 0 ? c.aliases.slice(0, 5).join(", ") : "None"}\n   - Status: ${c.status || "N/A"}, Phase: ${c.phase || "N/A"}\n   - Evidence: assigned=${c.evidence.assigned}, affinity=${c.evidence.affinity_weight.toFixed(2)}, sources=[${c.evidence.sources.join(",")}]\n   - ${aliasMatchSummary}`;
  }).join("\n\n");
  const recentProjectList = ctx.contact.recent_projects.length > 0 ? ctx.contact.recent_projects.map((p) => p.project_name).join(", ") : "None";
  return `TRANSCRIPT SEGMENT:\n"""\n${ctx.span.transcript_text}\n"""\n\nCALLER INFO:\n- Name: ${ctx.contact.contact_name || "Unknown"}\n- Is Floater: ${ctx.contact.floater_flag}\n- Recent Projects: ${recentProjectList}\n\nCANDIDATE PROJECTS (${ctx.candidates.length} total):\n${candidateList || "No candidates found"}\n\nAnalyze the transcript and determine which project this conversation is about.\nYou MUST include an exact quote from the transcript to use decision="assign".`;
}

// PROVIDER CALLS
async function callOpenAIAttribution(model: string, systemPrompt: string, userPrompt: string, apiKey: string): Promise<ProviderCallResult> {
  const t0 = Date.now();
  try {
    const resp = await fetch("https://api.openai.com/v1/chat/completions", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` }, body: JSON.stringify({ model, max_tokens: MAX_TOKENS, temperature: 0, messages: [{ role: "system", content: systemPrompt }, { role: "user", content: userPrompt }] }) });
    if (!resp.ok) { const errorText = await resp.text(); return { ok: false, provider: "openai", model, ms: Date.now() - t0, error_code: [401, 403, 404].includes(resp.status) ? "model_unavailable" : "openai_http_error", error_class: `status_${resp.status}:${errorText.slice(0, 120)}` }; }
    const payload = await resp.json();
    const rawContent = payload?.choices?.[0]?.message?.content || "";
    const tokens = (payload?.usage?.prompt_tokens || 0) + (payload?.usage?.completion_tokens || 0);
    const parsed = parseAttributionJson(rawContent);
    return { ok: true, provider: "openai", model, ms: Date.now() - t0, ...parsed, tokens_used: tokens, raw_response: payload };
  } catch (error: any) { return { ok: false, provider: "openai", model, ms: Date.now() - t0, error_code: "openai_fetch_error", error_class: error?.message || "unknown_error" }; }
}

async function callAnthropicAttribution(model: string, systemPrompt: string, userPrompt: string, apiKey: string): Promise<ProviderCallResult> {
  const t0 = Date.now();
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", { method: "POST", headers: { "Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" }, body: JSON.stringify({ model, max_tokens: MAX_TOKENS, temperature: 0, system: systemPrompt, messages: [{ role: "user", content: userPrompt }] }) });
    if (!resp.ok) { const errorText = await resp.text(); return { ok: false, provider: "anthropic", model, ms: Date.now() - t0, error_code: [401, 403, 404].includes(resp.status) ? "model_unavailable" : "anthropic_http_error", error_class: `status_${resp.status}:${errorText.slice(0, 120)}` }; }
    const payload = await resp.json();
    const textBlock = (payload?.content || []).find((block: any) => block?.type === "text");
    const rawContent = textBlock?.text || "";
    const tokens = (payload?.usage?.input_tokens || 0) + (payload?.usage?.output_tokens || 0);
    const parsed = parseAttributionJson(rawContent);
    return { ok: true, provider: "anthropic", model, ms: Date.now() - t0, ...parsed, tokens_used: tokens, raw_response: payload };
  } catch (error: any) { return { ok: false, provider: "anthropic", model, ms: Date.now() - t0, error_code: "anthropic_fetch_error", error_class: error?.message || "unknown_error" }; }
}

// CASCADE ENGINE
function applyGuardrails(result: ProviderCallResult, transcript: string): { decision: "assign" | "review" | "none"; validatedAnchors: Anchor[]; rejectedStaffAnchors: number } {
  if (!result.ok || !result.decision) return { decision: "review", validatedAnchors: [], rejectedStaffAnchors: 0 };
  let decision = result.decision;
  const { valid: hasValidAnchor, validatedAnchors, rejectedStaffAnchors } = validateAnchorQuotes(result.anchors || [], transcript);
  if (decision === "assign" && !hasValidAnchor) decision = "review";
  if (decision === "assign" && !hasStrongAnchor(validatedAnchors)) decision = "review";
  const confidence = result.confidence ?? 0;
  if (decision === "assign" && confidence < THRESHOLD_AUTO_ASSIGN) decision = "review";
  if (confidence < THRESHOLD_REVIEW) decision = "none";
  return { decision, validatedAnchors, rejectedStaffAnchors };
}

async function runAttributionCascade(params: { systemPrompt: string; userPrompt: string; transcript: string; openaiModels: string[]; anthropicModels: string[]; openaiKey: string | null; anthropicKey: string | null; stageTimeoutMs: number; maxStages: number }): Promise<{ candidate: CascadeCandidate | null; warnings: string[]; trace: Record<string, unknown>[]; model_disagreement: boolean }> {
  const warnings: string[] = [];
  const trace: Record<string, unknown>[] = [];
  let disagreementFallback: CascadeCandidate | null = null;
  let model_disagreement = false;

  for (let i = 0; i < params.maxStages; i++) {
    const stage = i + 1;
    const openaiModel = params.openaiModels[i];
    const anthropicModel = params.anthropicModels[i];
    if (!openaiModel && !anthropicModel) break;

    const openaiPromise = openaiModel && params.openaiKey
      ? withTimeout(callOpenAIAttribution(openaiModel, params.systemPrompt, params.userPrompt, params.openaiKey), params.stageTimeoutMs, `openai_stage_${stage}`).catch((error: any): ProviderCallResult => ({ ok: false, provider: "openai", model: openaiModel, ms: params.stageTimeoutMs, error_code: "provider_timeout", error_class: error?.message || "timeout" }))
      : Promise.resolve(openaiModel ? { ok: false, provider: "openai" as Provider, model: openaiModel, ms: 0, error_code: "missing_api_key", error_class: "OPENAI_API_KEY_not_set" } as ProviderCallResult : null);

    const anthropicPromise = anthropicModel && params.anthropicKey
      ? withTimeout(callAnthropicAttribution(anthropicModel, params.systemPrompt, params.userPrompt, params.anthropicKey), params.stageTimeoutMs, `anthropic_stage_${stage}`).catch((error: any): ProviderCallResult => ({ ok: false, provider: "anthropic", model: anthropicModel, ms: params.stageTimeoutMs, error_code: "provider_timeout", error_class: error?.message || "timeout" }))
      : Promise.resolve(anthropicModel ? { ok: false, provider: "anthropic" as Provider, model: anthropicModel, ms: 0, error_code: "missing_api_key", error_class: "ANTHROPIC_API_KEY_not_set" } as ProviderCallResult : null);

    const [openaiResult, anthropicResult] = await Promise.all([openaiPromise, anthropicPromise]);
    const openaiGuarded = openaiResult ? applyGuardrails(openaiResult, params.transcript) : null;
    const anthropicGuarded = anthropicResult ? applyGuardrails(anthropicResult, params.transcript) : null;

    trace.push({ stage, openai: openaiResult ? { ok: openaiResult.ok, model: openaiResult.model, project_id: openaiResult.project_id || null, decision: openaiGuarded?.decision || null, confidence: openaiResult.confidence ?? null, anchors: openaiGuarded?.validatedAnchors?.length ?? 0, error_code: openaiResult.error_code || null, ms: openaiResult.ms, tokens: openaiResult.tokens_used || 0 } : null, anthropic: anthropicResult ? { ok: anthropicResult.ok, model: anthropicResult.model, project_id: anthropicResult.project_id || null, decision: anthropicGuarded?.decision || null, confidence: anthropicResult.confidence ?? null, anchors: anthropicGuarded?.validatedAnchors?.length ?? 0, error_code: anthropicResult.error_code || null, ms: anthropicResult.ms, tokens: anthropicResult.tokens_used || 0 } : null });

    const openaiValid = !!openaiResult?.ok && openaiGuarded?.decision !== undefined;
    const anthropicValid = !!anthropicResult?.ok && anthropicGuarded?.decision !== undefined;

    if (openaiValid && anthropicValid) {
      const bothAssign = openaiGuarded!.decision === "assign" && anthropicGuarded!.decision === "assign";
      const sameProject = openaiResult!.project_id === anthropicResult!.project_id;

      if (bothAssign && sameProject) {
        const preferred = (openaiResult!.confidence ?? 0) > (anthropicResult!.confidence ?? 0) ? openaiResult! : anthropicResult!;
        const preferredAnchors = preferred === openaiResult ? openaiGuarded!.validatedAnchors : anthropicGuarded!.validatedAnchors;
        warnings.push(`cascade_stage_${stage}_agreement`);
        return { candidate: { provider: preferred.provider, model: preferred.model, stage, project_id: preferred.project_id!, confidence: preferred.confidence!, decision: "assign", reasoning: preferred.reasoning!, anchors: preferredAnchors, suggested_aliases: preferred.suggested_aliases, tokens_used: (openaiResult!.tokens_used || 0) + (anthropicResult!.tokens_used || 0), raw_response: { openai: openaiResult!.raw_response, anthropic: anthropicResult!.raw_response } }, warnings, trace, model_disagreement: false };
      }

      model_disagreement = true;
      warnings.push(`cascade_stage_${stage}_disagreement`);
      const openaiScore = (openaiGuarded!.decision === "assign" ? 10 : 0) + (openaiResult!.confidence ?? 0);
      const anthropicScore = (anthropicGuarded!.decision === "assign" ? 10 : 0) + (anthropicResult!.confidence ?? 0);
      const better = openaiScore >= anthropicScore ? openaiResult! : anthropicResult!;
      const betterAnchors = better === openaiResult ? openaiGuarded!.validatedAnchors : anthropicGuarded!.validatedAnchors;
      const betterDecision = better === openaiResult ? openaiGuarded!.decision : anthropicGuarded!.decision;
      disagreementFallback = { provider: better.provider, model: better.model, stage, project_id: better.project_id!, confidence: better.confidence!, decision: betterDecision, reasoning: better.reasoning!, anchors: betterAnchors, suggested_aliases: better.suggested_aliases, tokens_used: (openaiResult!.tokens_used || 0) + (anthropicResult!.tokens_used || 0), raw_response: { openai: openaiResult!.raw_response, anthropic: anthropicResult!.raw_response } };
      continue;
    }

    if (openaiValid !== anthropicValid) {
      const winner = openaiValid ? openaiResult! : anthropicResult!;
      const winnerGuarded = openaiValid ? openaiGuarded! : anthropicGuarded!;
      warnings.push(`cascade_stage_${stage}_single_provider_accept_${winner.provider}`);
      return { candidate: { provider: winner.provider, model: winner.model, stage, project_id: winner.project_id!, confidence: winner.confidence!, decision: winnerGuarded.decision, reasoning: winner.reasoning!, anchors: winnerGuarded.validatedAnchors, suggested_aliases: winner.suggested_aliases, tokens_used: winner.tokens_used || 0, raw_response: winner.raw_response }, warnings, trace, model_disagreement: false };
    }

    warnings.push(`cascade_stage_${stage}_no_valid_output`);
  }

  if (disagreementFallback) {
    warnings.push("cascade_final_disagreement_forced_review");
    disagreementFallback.decision = "review";
    return { candidate: disagreementFallback, warnings, trace, model_disagreement: true };
  }
  return { candidate: null, warnings, trace, model_disagreement: false };
}

// MAIN HANDLER
Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "POST only" }), { status: 405, headers: { "Content-Type": "application/json" } });

  let body: any;
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: { "Content-Type": "application/json" } }); }

  const context_package: ContextPackage | null = body.context_package || null;
  const dry_run = body.dry_run === true;
  if (!context_package) return new Response(JSON.stringify({ error: "missing_context_package" }), { status: 400, headers: { "Content-Type": "application/json" } });
  const span_id = context_package.meta?.span_id;
  if (!span_id) return new Response(JSON.stringify({ error: "missing_span_id_in_context_package" }), { status: 400, headers: { "Content-Type": "application/json" } });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const openaiKey = Deno.env.get("OPENAI_API_KEY") || null;
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") || null;
  const openaiModels = parseModelList("AI_ROUTER_OPENAI_MODELS", DEFAULT_AI_ROUTER_OPENAI_MODELS);
  const anthropicModels = parseModelList("AI_ROUTER_ANTHROPIC_MODELS", DEFAULT_AI_ROUTER_ANTHROPIC_MODELS);
  const stageTimeoutMs = parsePositiveIntEnv("CASCADE_STAGE_TIMEOUT_MS", DEFAULT_CASCADE_STAGE_TIMEOUT_MS);
  const configuredMaxStages = parsePositiveIntEnv("CASCADE_MAX_STAGES", Math.max(openaiModels.length, anthropicModels.length));
  const maxStages = Math.max(1, Math.min(configuredMaxStages, Math.max(openaiModels.length, anthropicModels.length)));

  if (!openaiKey && !anthropicKey) return new Response(JSON.stringify({ ok: false, error: "missing_all_provider_keys", error_code: "config_error", prompt_version: PROMPT_VERSION }), { status: 500, headers: { "Content-Type": "application/json" } });

  let result: AttributionResult;
  let raw_response: any = null;
  let tokens_used = 0;
  let inference_ms = 0;
  let model_error = false;
  let cascade_winner_provider: string | null = null;
  let cascade_winner_model: string | null = null;
  let cascade_winner_stage = 0;
  let cascade_trace: Record<string, unknown>[] = [];
  let model_disagreement = false;

  const userPrompt = buildUserPrompt(context_package);

  try {
    const cascade = await runAttributionCascade({ systemPrompt: SYSTEM_PROMPT, userPrompt, transcript: context_package.span?.transcript_text || "", openaiModels, anthropicModels, openaiKey, anthropicKey, stageTimeoutMs, maxStages });
    cascade_trace = cascade.trace;
    model_disagreement = cascade.model_disagreement;
    inference_ms = Date.now() - t0;

    if (cascade.candidate) {
      cascade_winner_provider = cascade.candidate.provider;
      cascade_winner_model = cascade.candidate.model;
      cascade_winner_stage = cascade.candidate.stage;
      tokens_used = cascade.candidate.tokens_used;
      raw_response = cascade.candidate.raw_response;
      result = { span_id, project_id: cascade.candidate.project_id, confidence: cascade.candidate.confidence, decision: cascade.candidate.decision, reasoning: cascade.candidate.reasoning, anchors: cascade.candidate.anchors, suggested_aliases: cascade.candidate.suggested_aliases };
      if (cascade.warnings.length > 0) console.log(`[ai-router] Cascade: ${cascade.warnings.join(", ")}`);
    } else {
      model_error = true;
      result = { span_id, project_id: null, confidence: 0, decision: "review", reasoning: `cascade_exhausted: ${cascade.warnings.join(", ")}`, anchors: [] };
      console.log(`[ai-router] Cascade exhausted: ${cascade.warnings.join(", ")}`);
    }
  } catch (e: any) {
    console.error("[ai-router] Cascade error:", e.message);
    model_error = true;
    result = { span_id, project_id: null, confidence: 0, decision: "review", reasoning: `model_error: ${e.message}`, anchors: [] };
  }

  let applied = false;
  let applied_project_id: string | null = null;
  let gatekeeper_reason: string | null = null;

  if (!dry_run) {
    const { data: existingAttribution } = await db.from("span_attributions").select("attribution_lock").eq("span_id", span_id).maybeSingle();
    const currentLock = existingAttribution?.attribution_lock ?? null;
    const wouldApply = result.decision === "assign" && result.confidence >= THRESHOLD_AUTO_ASSIGN;
    const newLock = wouldApply ? "ai" : null;

    if (!canOverwriteLock(currentLock, newLock)) {
      gatekeeper_reason = currentLock === "human" ? "human_lock_present" : "ai_lock_preserved";
      console.log(`[ai-router] Lock preserved: current=${currentLock}, attempted=${newLock}`);
    } else {
      const { valid: hasValidAnchor } = validateAnchorQuotes(result.anchors, context_package.span?.transcript_text || "");
      if (result.decision === "assign" && result.confidence >= THRESHOLD_AUTO_ASSIGN && hasValidAnchor) { applied = true; applied_project_id = result.project_id; gatekeeper_reason = "auto_assigned"; }
      else if (result.decision === "review" || (result.confidence >= THRESHOLD_REVIEW && result.confidence < THRESHOLD_AUTO_ASSIGN)) { gatekeeper_reason = "needs_review"; }
      else { gatekeeper_reason = "no_match"; }
    }

    const attribution_lock = applied ? "ai" : null;
    const needs_review = result.decision === "review" || result.decision === "none";
    const model_id_str = cascade_winner_model || "cascade_exhausted";

    const { error: upsertErr } = await db.from("span_attributions").upsert({ span_id, project_id: result.project_id, confidence: result.confidence, decision: result.decision, reasoning: result.reasoning, anchors: result.anchors, suggested_aliases: result.suggested_aliases || [], prompt_version: PROMPT_VERSION, model_id: model_id_str, raw_response, tokens_used, inference_ms, attribution_lock, applied_project_id, applied_at_utc: applied ? new Date().toISOString() : null, needs_review, attributed_by: `ai-router-${PROMPT_VERSION}`, attributed_at: new Date().toISOString() }, { onConflict: "span_id,model_id,prompt_version", ignoreDuplicates: false });
    if (upsertErr) console.error("[ai-router] span_attributions upsert failed:", upsertErr.message, upsertErr.details);

    const interaction_id = context_package.meta?.interaction_id;
    const quoteVerified = result.anchors.length > 0;
    const strongAnchorPresent = hasStrongAnchor(result.anchors);
    const needsReviewQueue = result.decision !== "assign" || needs_review || !quoteVerified || !strongAnchorPresent || model_error || model_disagreement;

    if (needsReviewQueue) {
      const reason_codes = buildReasonCodes({ modelReasons: null, quoteVerified, strongAnchor: strongAnchorPresent, modelError: model_error, ambiguousContact: context_package.contact?.floater_flag === true, geoOnly: !strongAnchorPresent && result.anchors.some((a) => a.match_type === "city_or_location"), modelDisagreement: model_disagreement });
      const context_payload = { span_id, interaction_id, transcript_snippet: (context_package.span?.transcript_text || "").slice(0, 600), candidates: context_package.candidates?.map((c) => ({ project_id: c.project_id, name: c.project_name, evidence_tags: c.evidence?.sources || [] })) || [], anchors: result.anchors, cascade_winner_provider, cascade_winner_model, cascade_winner_stage, prompt_version: PROMPT_VERSION, created_at_utc: new Date().toISOString() };
      await upsertReviewQueue(db, { span_id, interaction_id: interaction_id || span_id, reasons: reason_codes, context_payload });
      console.log(`[ai-router] Created review_queue item for span ${span_id}, reasons: ${reason_codes.join(",")}`);
    } else {
      await resolveReviewQueue(db, span_id, "auto-applied by ai-router cascade");
      console.log(`[ai-router] Resolved review_queue item for span ${span_id} (auto-assigned)`);
    }
  }

  return new Response(JSON.stringify({ ok: true, span_id, project_id: result.project_id, confidence: result.confidence, decision: result.decision, reasoning: result.reasoning, anchors: result.anchors, suggested_aliases: result.suggested_aliases, gatekeeper: { applied, applied_project_id, reason: gatekeeper_reason }, model_error, model_disagreement, dry_run, cascade: { winner_provider: cascade_winner_provider, winner_model: cascade_winner_model, winner_stage: cascade_winner_stage, trace: cascade_trace }, prompt_version: PROMPT_VERSION, tokens_used, inference_ms, ms: Date.now() - t0 }), { status: 200, headers: { "Content-Type": "application/json" } });
});
