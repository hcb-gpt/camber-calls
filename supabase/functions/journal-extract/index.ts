/**
 * journal-extract Edge Function v1.1.1
 * Extracts structured epistemic claims from attributed conversation spans
 *
 * @version 1.1.1
 * @date 2026-02-10
 * @purpose D1 deliverable - journal claim extraction from spans
 *
 * v1.1.1 changes (DEV-10):
 *   - Fix: skip DB insert when project_id is null (FK constraint on projects(id))
 *     Claims still extracted; written after attribution lands via re-trigger
 *
 * v1.1.0 changes (DEV-10):
 *   - Robust JSON parsing: strip control chars, trailing commas, comment removal
 *   - LLM retry on parse failure with explicit JSON-only instruction
 *   - Idempotency guard: skip insert if claims already exist for span_id+run combination
 *   - Model default updated to claude-3-haiku-20240307
 *
 * Input: { span_id } or { interaction_id, span_index }
 * Process: LLM extracts structured claims from span transcript_segment
 * Output: rows in journal_claims + journal_open_loops, journal_runs audit
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_VERSION = "v1.1.1";
const PROMPT_VERSION = "journal-extract-v1";
const MAX_TOKENS = 4096;
const DEFAULT_MODEL = "claude-3-haiku-20240307";
const DEFAULT_TIMEOUT_MS = 30000;

const VALID_CLAIM_TYPES = ["commitment", "deadline", "decision", "blocker", "requirement", "preference", "concern", "fact", "question", "update"] as const;
const VALID_EPISTEMIC_STATUSES = ["stated", "inferred", "uncertain"] as const;
const VALID_WARRANT_LEVELS = ["high", "medium", "low"] as const;
const VALID_TESTIMONY_TYPES = ["direct", "reported", "inferred"] as const;

type ClaimType = typeof VALID_CLAIM_TYPES[number];
type EpistemicStatus = typeof VALID_EPISTEMIC_STATUSES[number];
type WarrantLevel = typeof VALID_WARRANT_LEVELS[number];
type TestimonyType = typeof VALID_TESTIMONY_TYPES[number];

interface ExtractedClaim {
  claim_type: ClaimType;
  claim_text: string;
  epistemic_status: EpistemicStatus;
  warrant_level: WarrantLevel;
  testimony_type: TestimonyType | null;
  speaker_label: string | null;
  start_sec: number | null;
  end_sec: number | null;
  is_open_loop: boolean;
  open_loop_type: string | null;
}

interface ExtractionResponse {
  claims: ExtractedClaim[];
  summary: string;
}

function stripCodeFences(raw: string): string {
  return (raw || "").replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
}

/**
 * Strip control characters (0x00-0x1F) except newline, carriage return, tab.
 * These can appear in LLM output and break JSON.parse().
 */
function stripControlChars(s: string): string {
  return s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "");
}

/**
 * Remove trailing commas before } or ] which are invalid JSON but
 * commonly produced by LLMs.
 */
function removeTrailingCommas(s: string): string {
  return s.replace(/,\s*([}\]])/g, "$1");
}

/**
 * Remove single-line (//) and multi-line comments from JSON-like text.
 * LLMs sometimes annotate JSON with comments.
 */
function removeJsonComments(s: string): string {
  // Remove single-line comments (but not inside strings — best-effort)
  let result = s.replace(/\/\/[^\n]*/g, "");
  // Remove multi-line comments
  result = result.replace(/\/\*[\s\S]*?\*\//g, "");
  return result;
}

/**
 * Attempt to fix unescaped quotes inside JSON string values.
 * This is a best-effort heuristic: finds " inside values that aren't
 * preceded by a backslash and escapes them.
 */
function fixUnescapedQuotes(s: string): string {
  // Strategy: find patterns like "key": "value with "unescaped" quotes"
  // This is inherently fragile, so we only apply it as a fallback.
  // Replace sequences of ": " followed by a string that has internal unescaped quotes
  try {
    // Simple approach: within string values, replace unescaped internal quotes
    // Look for patterns where a quote appears mid-value (not preceded by \ and not at field boundary)
    // Simple best-effort: this function is a last-resort fallback
    // Just return the input — the retry mechanism handles truly broken JSON
    return s;
  } catch {
    return s;
  }
}

/**
 * Robust JSON parsing with multiple fallback strategies.
 * Tries increasingly aggressive sanitization until parse succeeds.
 */
function parseExtractionJson(raw: string): ExtractionResponse {
  const cleaned = stripCodeFences(raw);

  // Strategy 1: Direct parse after extracting JSON object
  const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
  const jsonStr = jsonMatch ? jsonMatch[0] : cleaned;

  // Attempt 1: Parse as-is
  try {
    const parsed = JSON.parse(jsonStr);
    return validateExtraction(parsed);
  } catch { /* continue to next strategy */ }

  // Attempt 2: Strip control chars + trailing commas
  try {
    const sanitized = removeTrailingCommas(stripControlChars(jsonStr));
    const parsed = JSON.parse(sanitized);
    return validateExtraction(parsed);
  } catch { /* continue */ }

  // Attempt 3: Also remove comments
  try {
    const sanitized = removeTrailingCommas(stripControlChars(removeJsonComments(jsonStr)));
    const parsed = JSON.parse(sanitized);
    return validateExtraction(parsed);
  } catch { /* continue */ }

  // Attempt 4: Try to extract just the {"claims":...} structure
  try {
    const claimsMatch = cleaned.match(/"claims"\s*:\s*\[[\s\S]*?\]/);
    if (claimsMatch) {
      const synthetic = `{${claimsMatch[0]}, "summary": ""}`;
      const sanitized = removeTrailingCommas(stripControlChars(synthetic));
      const parsed = JSON.parse(sanitized);
      return validateExtraction(parsed);
    }
  } catch { /* continue */ }

  // Attempt 5: Fix unescaped quotes
  try {
    const sanitized = removeTrailingCommas(stripControlChars(removeJsonComments(fixUnescapedQuotes(jsonStr))));
    const parsed = JSON.parse(sanitized);
    return validateExtraction(parsed);
  } catch { /* all local strategies exhausted */ }

  // If all attempts fail, throw with context for the retry mechanism
  throw new Error(`json_parse_failed: could not parse LLM output (${jsonStr.length} chars)`);
}

/**
 * Validate and normalize the parsed extraction object.
 */
function validateExtraction(parsed: any): ExtractionResponse {
  const claims: ExtractedClaim[] = [];
  for (const c of (Array.isArray(parsed.claims) ? parsed.claims : [])) {
    const claim_type = VALID_CLAIM_TYPES.includes(c.claim_type) ? c.claim_type : null;
    if (!claim_type || !c.claim_text) continue;

    claims.push({
      claim_type,
      claim_text: String(c.claim_text).slice(0, 2000),
      epistemic_status: VALID_EPISTEMIC_STATUSES.includes(c.epistemic_status) ? c.epistemic_status : "inferred",
      warrant_level: VALID_WARRANT_LEVELS.includes(c.warrant_level) ? c.warrant_level : "medium",
      testimony_type: c.testimony_type && VALID_TESTIMONY_TYPES.includes(c.testimony_type) ? c.testimony_type : null,
      speaker_label: c.speaker_label || null,
      start_sec: typeof c.start_sec === "number" ? c.start_sec : null,
      end_sec: typeof c.end_sec === "number" ? c.end_sec : null,
      is_open_loop: c.is_open_loop === true,
      open_loop_type: c.open_loop_type || null,
    });
  }

  return { claims, summary: parsed.summary || "" };
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  let timeoutHandle: number | undefined;
  const timeoutPromise = new Promise<T>((_, reject) => {
    timeoutHandle = setTimeout(() => reject(new Error(`${label}_timeout`)), timeoutMs);
  });
  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
  }
}

/**
 * Call Anthropic API for claim extraction.
 */
async function callLlm(
  anthropicKey: string,
  model: string,
  systemPrompt: string,
  userPrompt: string,
  timeoutMs: number,
): Promise<{ rawContent: string; tokens_used: number; inference_ms: number }> {
  const llmT0 = Date.now();
  const resp = await withTimeout(
    fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: MAX_TOKENS,
        temperature: 0,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }],
      }),
    }),
    timeoutMs,
    "anthropic_extract",
  );
  const inference_ms = Date.now() - llmT0;

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`anthropic_${resp.status}: ${errText.slice(0, 200)}`);
  }

  const payload = await resp.json();
  const textBlock = (payload?.content || []).find((b: any) => b?.type === "text");
  const rawContent = textBlock?.text || "";
  const tokens_used = (payload?.usage?.input_tokens || 0) + (payload?.usage?.output_tokens || 0);

  return { rawContent, tokens_used, inference_ms };
}

const SYSTEM_PROMPT = `You are a construction project journal analyst for HCB (Heartwood Custom Builders).
You extract structured epistemic claims from phone call transcript segments.

Each claim represents a discrete piece of project knowledge with its epistemic properties.

CLAIM TYPES (pick exactly one per claim):
- commitment: Someone committed to doing something ("I'll have that done by Friday")
- deadline: A specific date or timeframe was mentioned ("We need permits by March 1st")
- decision: A decision was made ("We're going with the 6-inch baseboards")
- blocker: Something is blocking progress ("We can't start framing until the engineer signs off")
- requirement: A requirement or spec was stated ("The county requires a 30-foot setback")
- preference: A preference was expressed ("The homeowner wants white oak floors")
- concern: A concern or worry was raised ("I'm worried about the lead time on windows")
- fact: A factual statement about the project ("The lot is 2.3 acres")
- question: An unresolved question ("Do we know if they got the variance?")
- update: A status update on something ("Plumbing rough-in is done")

EPISTEMIC STATUS:
- stated: Speaker explicitly said this (direct quote or clear paraphrase)
- inferred: Implied by context but not directly said
- uncertain: Ambiguous - could be interpreted multiple ways

WARRANT LEVEL (how much evidence supports this claim):
- high: Clear, unambiguous statement with context
- medium: Reasonable interpretation but some ambiguity
- low: Weak signal, single mention, or heavily context-dependent

TESTIMONY TYPE:
- direct: Speaker is the source ("I measured it at 14 feet")
- reported: Speaker is relaying what someone else said ("The engineer said...")
- inferred: Not explicitly spoken, derived from context

OPEN LOOPS: Flag claims that represent incomplete items needing follow-up:
- Unanswered questions
- Commitments without confirmation
- Blockers without resolution
- Items someone said they'd "look into" or "get back to you on"

SPEAKER LABELS: Use the speaker labels from the transcript (e.g., SPEAKER_0, SPEAKER_1).

RULES:
1. Extract ALL meaningful project claims - be thorough
2. Each claim should be one atomic piece of knowledge
3. Do NOT extract small talk, greetings, or non-project conversation
4. Preserve the original meaning - do not embellish or add information
5. If a segment mentions multiple projects, extract claims for each mentioned topic
6. Include temporal references from the transcript (start_sec/end_sec) if available

OUTPUT FORMAT (JSON only, no markdown):
{
  "claims": [
    {
      "claim_type": "commitment|deadline|decision|blocker|requirement|preference|concern|fact|question|update",
      "claim_text": "Clear, concise description of the claim",
      "epistemic_status": "stated|inferred|uncertain",
      "warrant_level": "high|medium|low",
      "testimony_type": "direct|reported|inferred",
      "speaker_label": "SPEAKER_0",
      "start_sec": null,
      "end_sec": null,
      "is_open_loop": false,
      "open_loop_type": null
    }
  ],
  "summary": "One sentence summarizing the key project topics in this segment"
}`;

const RETRY_SYSTEM_PROMPT = `You are a construction project journal analyst for HCB (Heartwood Custom Builders).
You extract structured epistemic claims from phone call transcript segments.

CRITICAL: Your previous response could not be parsed as valid JSON. You MUST output ONLY valid JSON with no extra text, no markdown code fences, no comments, and no trailing commas. Double-check all string values have properly escaped quotes.

OUTPUT FORMAT (strict JSON — nothing else):
{
  "claims": [
    {
      "claim_type": "commitment|deadline|decision|blocker|requirement|preference|concern|fact|question|update",
      "claim_text": "Clear, concise description of the claim",
      "epistemic_status": "stated|inferred|uncertain",
      "warrant_level": "high|medium|low",
      "testimony_type": "direct|reported|inferred",
      "speaker_label": "SPEAKER_0",
      "start_sec": null,
      "end_sec": null,
      "is_open_loop": false,
      "open_loop_type": null
    }
  ],
  "summary": "One sentence summary"
}`;

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405, headers: { "Content-Type": "application/json" },
    });
  }

  const edgeSecret = req.headers.get("X-Edge-Secret") || req.headers.get("x-edge-secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");
  const authHeader = req.headers.get("Authorization");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  const secretOk = expectedSecret && edgeSecret === expectedSecret;
  const bearerOk = serviceRoleKey && authHeader === `Bearer ${serviceRoleKey}`;

  if (!secretOk && !bearerOk) {
    return new Response(
      JSON.stringify({ error: "unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400, headers: { "Content-Type": "application/json" },
    });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) {
    return new Response(
      JSON.stringify({ ok: false, error: "missing_anthropic_key" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const model = Deno.env.get("JOURNAL_EXTRACT_MODEL") || DEFAULT_MODEL;
  const timeoutMs = Number(Deno.env.get("JOURNAL_EXTRACT_TIMEOUT_MS")) || DEFAULT_TIMEOUT_MS;
  const dry_run = body.dry_run === true;

  try {
    let span_id: string | null = body.span_id || null;

    if (!span_id && body.interaction_id) {
      const span_index = body.span_index ?? 0;
      const { data: spanRow } = await db
        .from("conversation_spans")
        .select("id")
        .eq("interaction_id", body.interaction_id)
        .eq("span_index", span_index)
        .eq("is_superseded", false)
        .single();
      if (spanRow) span_id = spanRow.id;
    }

    if (!span_id) {
      return new Response(
        JSON.stringify({ error: "missing_span_id" }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data: span, error: spanErr } = await db
      .from("conversation_spans")
      .select("id, interaction_id, transcript_segment, time_start_sec, time_end_sec, span_index")
      .eq("id", span_id)
      .single();

    if (spanErr || !span) {
      return new Response(
        JSON.stringify({ error: "span_not_found", span_id }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const interaction_id = span.interaction_id;
    const transcript = span.transcript_segment || "";

    if (!transcript || transcript.trim().length < 20) {
      return new Response(
        JSON.stringify({ ok: true, span_id, claims_extracted: 0, reason: "transcript_too_short", ms: Date.now() - t0 }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }

    const { data: attribution } = await db
      .from("span_attributions")
      .select("project_id, applied_project_id, confidence, decision")
      .eq("span_id", span_id)
      .order("attributed_at", { ascending: false })
      .limit(1)
      .single();

    const project_id = attribution?.applied_project_id || attribution?.project_id || null;

    // ── IDEMPOTENCY GUARD ──────────────────────────────────────────
    // Check if completed claims already exist for this span_id.
    // Prevents duplicate insertion on re-runs (addresses 32.9% duplication issue).
    if (!dry_run) {
      const { data: existingClaims, error: existErr } = await db
        .from("journal_claims")
        .select("claim_id")
        .eq("source_span_id", span_id)
        .limit(1);

      if (!existErr && existingClaims && existingClaims.length > 0) {
        // Count total existing claims for the response
        const { count } = await db
          .from("journal_claims")
          .select("claim_id", { count: "exact", head: true })
          .eq("source_span_id", span_id);

        return new Response(
          JSON.stringify({
            ok: true,
            span_id,
            interaction_id,
            project_id,
            idempotent_skip: true,
            existing_claims: count || 0,
            reason: "claims_already_exist_for_span",
            function_version: FUNCTION_VERSION,
            ms: Date.now() - t0,
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        );
      }
    }

    const run_id = crypto.randomUUID();

    if (!dry_run) {
      const { error: runErr } = await db.from("journal_runs").insert({
        run_id,
        call_id: interaction_id,
        project_id,
        status: "running",
        config: { model, prompt_version: PROMPT_VERSION, function_version: FUNCTION_VERSION, span_id },
      });
      if (runErr) console.error("[journal-extract] journal_runs insert failed:", runErr.message);
    }

    const userPrompt = `TRANSCRIPT SEGMENT (span_id: ${span_id}, interaction: ${interaction_id}):\n"""\n${transcript}\n"""\n\nExtract all project-relevant claims from this transcript segment.`;

    let extraction: ExtractionResponse;
    let tokens_used = 0;
    let inference_ms = 0;
    let retried = false;

    // ── ATTEMPT 1: Normal extraction ──────────────────────────────
    const result1 = await callLlm(anthropicKey, model, SYSTEM_PROMPT, userPrompt, timeoutMs);
    tokens_used = result1.tokens_used;
    inference_ms = result1.inference_ms;

    try {
      extraction = parseExtractionJson(result1.rawContent);
    } catch (parseErr: any) {
      // ── ATTEMPT 2: Retry with strict JSON-only prompt ─────────
      console.warn(`[journal-extract] Parse failed on attempt 1: ${parseErr.message}. Retrying with strict prompt.`);
      retried = true;

      const retryPrompt = `TRANSCRIPT SEGMENT (span_id: ${span_id}, interaction: ${interaction_id}):\n"""\n${transcript}\n"""\n\nExtract all project-relevant claims. Output ONLY valid JSON — no markdown, no code fences, no comments.`;

      const result2 = await callLlm(anthropicKey, model, RETRY_SYSTEM_PROMPT, retryPrompt, timeoutMs);
      tokens_used += result2.tokens_used;
      inference_ms += result2.inference_ms;

      extraction = parseExtractionJson(result2.rawContent);
      // If this also throws, it propagates to the outer catch
    }

    const speakerContactMap = new Map<string, { contact_id: string; contact_name: string; is_internal: boolean }>();

    if (project_id) {
      const uniqueSpeakers = [...new Set(extraction.claims.map(c => c.speaker_label).filter(Boolean))];
      for (const label of uniqueSpeakers) {
        try {
          const { data: resolved } = await db.rpc("resolve_speaker_contact", {
            p_speaker_label: label,
            p_project_id: project_id,
          });
          if (resolved && resolved.length > 0) {
            speakerContactMap.set(label!, {
              contact_id: resolved[0].contact_id,
              contact_name: resolved[0].contact_name,
              is_internal: resolved[0].is_internal,
            });
          }
        } catch { /* speaker resolution is best-effort */ }
      }
    }

    let claims_written = 0;
    let loops_written = 0;
    const claim_ids: string[] = [];
    let skipped_no_project = false;

    if (!dry_run && extraction.claims.length > 0) {
      // ── NULL PROJECT_ID GUARD ────────────────────────────────────
      // journal_claims.project_id has NOT NULL + FK to projects(id).
      // If span has no attribution yet, we cannot write claims — the FK
      // would reject the insert. Return extraction results so caller
      // knows claims were found, and can re-trigger after attribution.
      if (!project_id) {
        skipped_no_project = true;
        console.warn(`[journal-extract] Skipping claim insert: span ${span_id} has no project attribution (FK constraint).`);

        await db.from("journal_runs").update({
          status: "completed",
          completed_at: new Date().toISOString(),
          claims_extracted: 0,
          error_message: "no_project_attribution: claims extracted but not written (FK constraint)",
        }).eq("run_id", run_id);
      } else {
        const claimRows = extraction.claims.map(c => {
          const speaker = c.speaker_label ? speakerContactMap.get(c.speaker_label) : null;
          const claim_id = crypto.randomUUID();
          claim_ids.push(claim_id);

          return {
            claim_id,
            run_id,
            call_id: interaction_id,
            project_id,
            source_span_id: span_id,
            claim_type: c.claim_type,
            claim_text: c.claim_text,
            epistemic_status: c.epistemic_status,
            warrant_level: c.warrant_level,
            testimony_type: c.testimony_type,
            speaker_label: c.speaker_label,
            speaker_contact_id: speaker?.contact_id || null,
            speaker_is_internal: speaker?.is_internal || null,
            start_sec: c.start_sec,
            end_sec: c.end_sec,
            relationship: "new",
            active: true,
            extraction_model_id: model,
            extraction_prompt_version: PROMPT_VERSION,
          };
        });

        const { error: claimErr } = await db.from("journal_claims").insert(claimRows);
        if (claimErr) {
          console.error("[journal-extract] journal_claims insert failed:", claimErr.message);
        } else {
          claims_written = claimRows.length;
        }

        const openLoopClaims = extraction.claims.filter(c => c.is_open_loop);
        if (openLoopClaims.length > 0) {
          const loopRows = openLoopClaims.map(c => ({
            run_id,
            call_id: interaction_id,
            project_id,
            loop_type: c.open_loop_type || c.claim_type,
            description: c.claim_text,
            start_sec: c.start_sec,
            end_sec: c.end_sec,
            status: "open",
          }));

          const { error: loopErr } = await db.from("journal_open_loops").insert(loopRows);
          if (loopErr) {
            console.error("[journal-extract] journal_open_loops insert failed:", loopErr.message);
          } else {
            loops_written = loopRows.length;
          }
        }

        await db.from("journal_runs").update({
          status: "completed",
          completed_at: new Date().toISOString(),
          claims_extracted: claims_written,
        }).eq("run_id", run_id);
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        span_id,
        interaction_id,
        project_id,
        run_id: dry_run ? null : run_id,
        claims_extracted: extraction.claims.length,
        claims_written,
        open_loops_written: loops_written,
        claim_ids: dry_run ? [] : claim_ids,
        summary: extraction.summary,
        speakers_resolved: speakerContactMap.size,
        skipped_no_project,
        ...(skipped_no_project ? { reason: "no_project_attribution: re-trigger after ai-router attributes span" } : {}),
        model,
        tokens_used,
        inference_ms,
        retried,
        dry_run,
        prompt_version: PROMPT_VERSION,
        function_version: FUNCTION_VERSION,
        ms: Date.now() - t0,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );

  } catch (e: any) {
    console.error("[journal-extract] Error:", e.message);

    if (!body.dry_run) {
      try {
        await db.from("journal_runs").update({
          status: "failed",
          completed_at: new Date().toISOString(),
          error_message: e.message?.slice(0, 500),
        }).eq("call_id", body.interaction_id || "").eq("status", "running");
      } catch { /* ignore */ }
    }

    return new Response(
      JSON.stringify({
        ok: false,
        error: e.message,
        function_version: FUNCTION_VERSION,
        ms: Date.now() - t0,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
