/**
 * segment-llm Edge Function v1.4.0
 * LLM-powered call segmenter: identifies project-switch boundaries in transcripts
 *
 * @version 1.4.0
 * @date 2026-02-08
 * @purpose Segment transcripts into N spans for multi-project attribution
 *
 * Auth: X-Edge-Secret + provenance allowlist (verify_jwt: false)
 * Called from: segment-call only
 *
 * STOPLINES (from CLAUDE.md):
 * - Never assigns project truth
 * - Never writes DB
 * - Never drops transcript content
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SEGMENT_LLM_VERSION = "segment-llm_v1.4.0";

// ============================================================
// STRUCTURED LOGGING (per GPT-DEV-6 spec)
// ============================================================
type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR";

function structuredLog(
  level: LogLevel,
  event: string,
  requestId: string,
  interactionId: string | null,
  extra: Record<string, unknown> = {},
): void {
  const log = {
    ts: new Date().toISOString(),
    level,
    service: "edge-function",
    function: "segment-llm",
    event,
    interaction_id: interactionId,
    generation: null, // segment-llm doesn't track generation
    request_id: requestId,
    correlation_id: `${interactionId || "unknown"}:0:${requestId}`,
    segmenter_version: SEGMENT_LLM_VERSION,
    ...extra,
  };
  if (level === "ERROR") {
    console.error(JSON.stringify(log));
  } else {
    console.log(JSON.stringify(log));
  }
}

// ============================================================
// AUTH CONFIGURATION
// ============================================================
const ALLOWED_PROVENANCE_SOURCES = ["segment-call", "admin-reseed", "edge", "test"];

// ============================================================
// GUARDRAIL DEFAULTS
// ============================================================
const DEFAULT_MAX_SEGMENTS = 10;
const DEFAULT_MIN_SEGMENT_CHARS = 200;
const DEFAULT_CASCADE_STAGE_TIMEOUT_MS = 12000;
const DEFAULT_CASCADE_BOUNDARY_TOLERANCE_CHARS = 120;
const DEFAULT_SEGMENT_LLM_OPENAI_MODELS = [
  "gpt-4o-mini",
  "gpt-4o",
  "gpt-4.1-mini",
  "gpt-4.1",
];
const DEFAULT_SEGMENT_LLM_ANTHROPIC_MODELS = [
  "claude-3-haiku-20240307",
  "claude-3-5-haiku-20241022",
  "claude-3-5-sonnet-20241022",
  "claude-3-7-sonnet-20250219",
];

// ============================================================
// TYPES
// ============================================================
interface Segment {
  span_index: number;
  char_start: number;
  char_end: number;
  boundary_reason: string;
  confidence: number;
  boundary_quote: string | null;
}

interface SegmentLLMOutput {
  ok: boolean;
  segmenter_version: string;
  segments: Segment[];
  warnings: string[];
  error_code?: string;
  ms?: number;
}

type Provider = "openai" | "anthropic";

interface ProviderCallResult {
  ok: boolean;
  provider: Provider;
  model: string;
  ms: number;
  segments?: Segment[];
  warnings?: string[];
  error_code?: string;
  error_class?: string;
}

interface CascadeCandidate {
  provider: Provider;
  model: string;
  stage: number;
  segments: Segment[];
  warnings: string[];
}

interface CascadeMetadata {
  provider: Provider;
  model: string;
  stage: number;
  openai_models: string[];
  anthropic_models: string[];
  stage_timeout_ms: number;
  boundary_tolerance_chars: number;
}

// ============================================================
// LLM PROMPT
// ============================================================
const SEGMENTATION_PROMPT = `You are a call transcript segmenter for a construction company.

Your task: Identify boundaries where the conversation switches from one PROJECT to another.

RULES:
1. A "project" is a specific construction job (e.g., "Johnson Residence", "Smith Project", "the Hurley job")
2. Split ONLY when there's a clear topic/project switch
3. Do NOT split for:
   - Speaker changes within same project discussion
   - Brief tangents that return to same project
   - General greetings/closings
4. Each segment must be >= {MIN_CHARS} characters (merge smaller ones into previous)
5. Maximum {MAX_SEGMENTS} segments total
6. Segments must be contiguous (no gaps, no overlaps)

OUTPUT FORMAT (JSON only, no markdown):
{
  "segments": [
    {
      "span_index": 0,
      "char_start": 0,
      "char_end": <end_char>,
      "boundary_reason": "initial_project|topic_shift|project_switch",
      "confidence": 0.0-1.0,
      "boundary_quote": "<exact quote <=50 chars showing the switch>"
    }
  ]
}

TRANSCRIPT:
{TRANSCRIPT}`;

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

function stripCodeFences(raw: string): string {
  return (raw || "").replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
}

function parseSegmentsJson(raw: string): Segment[] {
  const cleaned = stripCodeFences(raw);
  const parsed = JSON.parse(cleaned);
  if (!Array.isArray(parsed?.segments) || parsed.segments.length === 0) {
    throw new Error("no_segments");
  }
  return parsed.segments as Segment[];
}

function applySegmentGuardrails(
  inputSegments: Segment[],
  transcript: string,
  transcriptLength: number,
  minSegmentChars: number,
  maxSegments: number,
): { segments: Segment[]; warnings: string[] } {
  const warnings: string[] = [];
  let segments = inputSegments.map((seg, idx) => {
    const charStart = Number(seg.char_start);
    const charEnd = Number(seg.char_end);
    const confidence = Number(seg.confidence);
    return {
      span_index: idx,
      char_start: Number.isFinite(charStart) ? charStart : 0,
      char_end: Number.isFinite(charEnd) ? charEnd : transcriptLength,
      boundary_reason: typeof seg.boundary_reason === "string" && seg.boundary_reason.length > 0
        ? seg.boundary_reason
        : "model_boundary",
      confidence: Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0.5,
      boundary_quote: typeof seg.boundary_quote === "string" ? seg.boundary_quote : null,
    };
  });

  segments = segments.map((seg) => ({
    ...seg,
    char_start: Math.max(0, Math.min(seg.char_start, transcriptLength)),
    char_end: Math.max(0, Math.min(seg.char_end, transcriptLength)),
  }));

  segments.sort((a, b) => a.char_start - b.char_start);
  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  for (let i = 1; i < segments.length; i++) {
    if (segments[i].char_start !== segments[i - 1].char_end) {
      warnings.push(`gap_fixed_at_index_${i}`);
      segments[i].char_start = segments[i - 1].char_end;
    }
  }

  if (segments[0].char_start !== 0) {
    warnings.push("first_segment_start_fixed");
    segments[0].char_start = 0;
  }
  if (segments[segments.length - 1].char_end !== transcriptLength) {
    warnings.push("last_segment_end_fixed");
    segments[segments.length - 1].char_end = transcriptLength;
  }

  let merged = true;
  while (merged && segments.length > 1) {
    merged = false;
    for (let i = segments.length - 1; i >= 0; i--) {
      const size = segments[i].char_end - segments[i].char_start;
      if (size < minSegmentChars && segments.length > 1) {
        if (i > 0) {
          segments[i - 1].char_end = segments[i].char_end;
          segments[i - 1].boundary_reason += "_merged_undersized";
          segments.splice(i, 1);
          warnings.push(`merged_undersized_segment_${i}`);
          merged = true;
          break;
        }
        if (i === 0 && segments.length > 1) {
          segments[1].char_start = segments[0].char_start;
          segments.splice(0, 1);
          warnings.push("merged_undersized_first_segment");
          merged = true;
          break;
        }
      }
    }
  }

  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  while (segments.length > maxSegments) {
    let minConfIdx = 1;
    let minConf = segments[1].confidence;
    for (let i = 2; i < segments.length; i++) {
      if (segments[i].confidence < minConf) {
        minConf = segments[i].confidence;
        minConfIdx = i;
      }
    }
    segments[minConfIdx - 1].char_end = segments[minConfIdx].char_end;
    segments.splice(minConfIdx, 1);
    warnings.push(`merged_low_confidence_segment_${minConfIdx}`);
  }

  segments = segments.filter((seg) => {
    if (seg.char_end <= seg.char_start) {
      warnings.push(`removed_zero_length_segment_${seg.span_index}`);
      return false;
    }
    return true;
  }).map((seg, idx) => ({ ...seg, span_index: idx }));

  segments = segments.map((seg) => {
    const quote = seg.boundary_quote ? seg.boundary_quote.slice(0, 50) : null;
    if (quote && transcript && !transcript.includes(quote)) {
      warnings.push(`boundary_quote_not_found_${seg.span_index}`);
      return { ...seg, boundary_quote: null };
    }
    return { ...seg, boundary_quote: quote };
  });

  return { segments, warnings };
}

function segmentsAgreeWithinTolerance(
  a: Segment[],
  b: Segment[],
  toleranceChars: number,
): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const startDiff = Math.abs(a[i].char_start - b[i].char_start);
    const endDiff = Math.abs(a[i].char_end - b[i].char_end);
    if (startDiff > toleranceChars || endDiff > toleranceChars) return false;
  }
  return true;
}

function pickDisagreementWinner(a: ProviderCallResult, b: ProviderCallResult): ProviderCallResult {
  const aWarnings = a.warnings?.length || 0;
  const bWarnings = b.warnings?.length || 0;
  const aSegments = a.segments?.length || 0;
  const bSegments = b.segments?.length || 0;
  const aScore = (aSegments * 10) - aWarnings;
  const bScore = (bSegments * 10) - bWarnings;
  return aScore >= bScore ? a : b;
}

async function callOpenAIModel(
  model: string,
  prompt: string,
  apiKey: string,
  transcript: string,
  transcriptLength: number,
  minSegmentChars: number,
  maxSegments: number,
): Promise<ProviderCallResult> {
  const t0 = Date.now();
  try {
    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        temperature: 0,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!resp.ok) {
      const errorText = await resp.text();
      const isUnavailable = resp.status === 401 || resp.status === 403 || resp.status === 404;
      return {
        ok: false,
        provider: "openai",
        model,
        ms: Date.now() - t0,
        error_code: isUnavailable ? "model_unavailable" : "openai_http_error",
        error_class: `status_${resp.status}:${errorText.slice(0, 120)}`,
      };
    }

    const payload = await resp.json();
    const rawContent = payload?.choices?.[0]?.message?.content || "";
    const parsedSegments = parseSegmentsJson(rawContent);
    const guarded = applySegmentGuardrails(
      parsedSegments,
      transcript,
      transcriptLength,
      minSegmentChars,
      maxSegments,
    );

    if (guarded.segments.length === 0) {
      return {
        ok: false,
        provider: "openai",
        model,
        ms: Date.now() - t0,
        error_code: "all_segments_invalid",
        error_class: "guardrail_filtered",
      };
    }

    return {
      ok: true,
      provider: "openai",
      model,
      ms: Date.now() - t0,
      segments: guarded.segments,
      warnings: guarded.warnings,
    };
  } catch (error: any) {
    return {
      ok: false,
      provider: "openai",
      model,
      ms: Date.now() - t0,
      error_code: "openai_fetch_error",
      error_class: error?.message || "unknown_error",
    };
  }
}

async function callAnthropicModel(
  model: string,
  prompt: string,
  apiKey: string,
  transcript: string,
  transcriptLength: number,
  minSegmentChars: number,
  maxSegments: number,
): Promise<ProviderCallResult> {
  const t0 = Date.now();
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        temperature: 0,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!resp.ok) {
      const errorText = await resp.text();
      const isUnavailable = resp.status === 401 || resp.status === 403 || resp.status === 404;
      return {
        ok: false,
        provider: "anthropic",
        model,
        ms: Date.now() - t0,
        error_code: isUnavailable ? "model_unavailable" : "anthropic_http_error",
        error_class: `status_${resp.status}:${errorText.slice(0, 120)}`,
      };
    }

    const payload = await resp.json();
    const textBlock = (payload?.content || []).find((block: any) => block?.type === "text");
    const rawContent = textBlock?.text || "";
    const parsedSegments = parseSegmentsJson(rawContent);
    const guarded = applySegmentGuardrails(
      parsedSegments,
      transcript,
      transcriptLength,
      minSegmentChars,
      maxSegments,
    );

    if (guarded.segments.length === 0) {
      return {
        ok: false,
        provider: "anthropic",
        model,
        ms: Date.now() - t0,
        error_code: "all_segments_invalid",
        error_class: "guardrail_filtered",
      };
    }

    return {
      ok: true,
      provider: "anthropic",
      model,
      ms: Date.now() - t0,
      segments: guarded.segments,
      warnings: guarded.warnings,
    };
  } catch (error: any) {
    return {
      ok: false,
      provider: "anthropic",
      model,
      ms: Date.now() - t0,
      error_code: "anthropic_fetch_error",
      error_class: error?.message || "unknown_error",
    };
  }
}

async function runSegmentationCascade(params: {
  prompt: string;
  transcript: string;
  transcriptLength: number;
  minSegmentChars: number;
  maxSegments: number;
  openaiModels: string[];
  anthropicModels: string[];
  openaiKey: string | null;
  anthropicKey: string | null;
  stageTimeoutMs: number;
  maxStages: number;
  boundaryToleranceChars: number;
}): Promise<{ candidate: CascadeCandidate | null; warnings: string[]; trace: Record<string, unknown>[] }> {
  const warnings: string[] = [];
  const trace: Record<string, unknown>[] = [];
  let disagreementFallback: CascadeCandidate | null = null;

  for (let i = 0; i < params.maxStages; i++) {
    const stage = i + 1;
    const openaiModel = params.openaiModels[i];
    const anthropicModel = params.anthropicModels[i];
    if (!openaiModel && !anthropicModel) break;

    const openaiPromise = openaiModel && params.openaiKey
      ? withTimeout(
        callOpenAIModel(
          openaiModel,
          params.prompt,
          params.openaiKey,
          params.transcript,
          params.transcriptLength,
          params.minSegmentChars,
          params.maxSegments,
        ),
        params.stageTimeoutMs,
        `openai_stage_${stage}`,
      ).catch((error: any) =>
        ({
          ok: false,
          provider: "openai",
          model: openaiModel,
          ms: params.stageTimeoutMs,
          error_code: "provider_timeout",
          error_class: error?.message || "timeout",
        }) as ProviderCallResult
      )
      : Promise.resolve(
        openaiModel
          ? ({
            ok: false,
            provider: "openai",
            model: openaiModel,
            ms: 0,
            error_code: "missing_api_key",
            error_class: "OPENAI_API_KEY_not_set",
          } as ProviderCallResult)
          : null,
      );

    const anthropicPromise = anthropicModel && params.anthropicKey
      ? withTimeout(
        callAnthropicModel(
          anthropicModel,
          params.prompt,
          params.anthropicKey,
          params.transcript,
          params.transcriptLength,
          params.minSegmentChars,
          params.maxSegments,
        ),
        params.stageTimeoutMs,
        `anthropic_stage_${stage}`,
      ).catch((error: any) =>
        ({
          ok: false,
          provider: "anthropic",
          model: anthropicModel,
          ms: params.stageTimeoutMs,
          error_code: "provider_timeout",
          error_class: error?.message || "timeout",
        }) as ProviderCallResult
      )
      : Promise.resolve(
        anthropicModel
          ? ({
            ok: false,
            provider: "anthropic",
            model: anthropicModel,
            ms: 0,
            error_code: "missing_api_key",
            error_class: "ANTHROPIC_API_KEY_not_set",
          } as ProviderCallResult)
          : null,
      );

    const [openaiResult, anthropicResult] = await Promise.all([openaiPromise, anthropicPromise]);

    trace.push({
      stage,
      openai: openaiResult
        ? {
          ok: openaiResult.ok,
          model: openaiResult.model,
          segments: openaiResult.segments?.length ?? 0,
          error_code: openaiResult.error_code || null,
          error_class: openaiResult.error_class || null,
          ms: openaiResult.ms,
        }
        : null,
      anthropic: anthropicResult
        ? {
          ok: anthropicResult.ok,
          model: anthropicResult.model,
          segments: anthropicResult.segments?.length ?? 0,
          error_code: anthropicResult.error_code || null,
          error_class: anthropicResult.error_class || null,
          ms: anthropicResult.ms,
        }
        : null,
    });

    const openaiValid = !!openaiResult?.ok && !!openaiResult.segments?.length;
    const anthropicValid = !!anthropicResult?.ok && !!anthropicResult.segments?.length;

    if (openaiValid && anthropicValid) {
      const agreed = segmentsAgreeWithinTolerance(
        openaiResult!.segments!,
        anthropicResult!.segments!,
        params.boundaryToleranceChars,
      );

      if (agreed) {
        const preferred = pickDisagreementWinner(openaiResult!, anthropicResult!);
        warnings.push(`cascade_stage_${stage}_agreement`);
        return {
          candidate: {
            provider: preferred.provider,
            model: preferred.model,
            stage,
            segments: preferred.segments!,
            warnings: preferred.warnings || [],
          },
          warnings,
          trace,
        };
      }

      const tieBreak = pickDisagreementWinner(openaiResult!, anthropicResult!);
      disagreementFallback = {
        provider: tieBreak.provider,
        model: tieBreak.model,
        stage,
        segments: tieBreak.segments!,
        warnings: tieBreak.warnings || [],
      };
      warnings.push(`cascade_stage_${stage}_disagreement`);
      continue;
    }

    if (openaiValid !== anthropicValid) {
      const winner = openaiValid ? openaiResult! : anthropicResult!;
      warnings.push(`cascade_stage_${stage}_single_provider_accept_${winner.provider}`);
      return {
        candidate: {
          provider: winner.provider,
          model: winner.model,
          stage,
          segments: winner.segments!,
          warnings: winner.warnings || [],
        },
        warnings,
        trace,
      };
    }

    warnings.push(`cascade_stage_${stage}_no_valid_output`);
  }

  if (disagreementFallback) {
    warnings.push("cascade_final_stage_disagreement_tiebreak");
    return { candidate: disagreementFallback, warnings, trace };
  }

  return { candidate: null, warnings, trace };
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

  // ============================================================
  // AUTH GATE: X-Edge-Secret + provenance allowlist
  // ============================================================
  const edgeSecretHeader = req.headers.get("X-Edge-Secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const provenanceSource = body.source || "unknown";

  // Strict auth: X-Edge-Secret + valid provenance
  const hasValidAuth = expectedSecret &&
    edgeSecretHeader === expectedSecret &&
    ALLOWED_PROVENANCE_SOURCES.includes(provenanceSource);

  if (!hasValidAuth) {
    console.error(
      `[segment-llm] Auth failed: source=${provenanceSource}, hasSecret=${!!edgeSecretHeader}`,
    );
    return new Response(
      JSON.stringify({
        ok: false,
        error: "unauthorized",
        error_code: "auth_failed",
        hint: "Requires X-Edge-Secret with valid provenance source",
        version: SEGMENT_LLM_VERSION,
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  console.log(`[segment-llm] Auth passed: source=${provenanceSource}`);

  // ============================================================
  // INPUT VALIDATION
  // ============================================================
  const {
    interaction_id,
    transcript,
    max_segments = DEFAULT_MAX_SEGMENTS,
    min_segment_chars = DEFAULT_MIN_SEGMENT_CHARS,
  } = body;

  if (!interaction_id) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "missing_interaction_id",
        error_code: "bad_request",
        version: SEGMENT_LLM_VERSION,
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  if (!transcript || typeof transcript !== "string") {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "missing_or_invalid_transcript",
        error_code: "bad_request",
        version: SEGMENT_LLM_VERSION,
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const transcriptLength = transcript.length;
  const requestId = req.headers.get("x-request-id") || crypto.randomUUID();
  const caller = provenanceSource;

  // Structured log: segment_llm_request
  structuredLog("INFO", "segment_llm_request", requestId, interaction_id, {
    transcript_chars: transcriptLength,
    caller,
    params: { max_segments, min_segment_chars },
  });

  console.log(
    `[segment-llm] Processing: interaction_id=${interaction_id}, len=${transcriptLength}`,
  );

  // ============================================================
  // SHORT TRANSCRIPT FAST PATH
  // ============================================================
  if (transcriptLength < min_segment_chars * 2) {
    // Too short for meaningful segmentation - return single span
    console.log(`[segment-llm] Short transcript (${transcriptLength} chars), returning single span`);
    return new Response(
      JSON.stringify({
        ok: true,
        segmenter_version: SEGMENT_LLM_VERSION,
        segments: [
          {
            span_index: 0,
            char_start: 0,
            char_end: transcriptLength,
            boundary_reason: "full_call_short",
            confidence: 1.0,
            boundary_quote: null,
          },
        ],
        warnings: ["transcript_too_short_for_segmentation"],
        ms: Date.now() - t0,
      } as SegmentLLMOutput),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  const prompt = SEGMENTATION_PROMPT
    .replace("{TRANSCRIPT}", transcript)
    .replace("{MIN_CHARS}", String(min_segment_chars))
    .replace("{MAX_SEGMENTS}", String(max_segments));

  const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? null;
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? null;
  const openaiModels = parseModelList("SEGMENT_LLM_OPENAI_MODELS", DEFAULT_SEGMENT_LLM_OPENAI_MODELS);
  const anthropicModels = parseModelList(
    "SEGMENT_LLM_ANTHROPIC_MODELS",
    DEFAULT_SEGMENT_LLM_ANTHROPIC_MODELS,
  );
  const stageTimeoutMs = parsePositiveIntEnv("CASCADE_STAGE_TIMEOUT_MS", DEFAULT_CASCADE_STAGE_TIMEOUT_MS);
  const boundaryToleranceChars = parsePositiveIntEnv(
    "CASCADE_BOUNDARY_TOLERANCE_CHARS",
    DEFAULT_CASCADE_BOUNDARY_TOLERANCE_CHARS,
  );
  const configuredMaxStages = parsePositiveIntEnv(
    "CASCADE_MAX_STAGES",
    Math.max(openaiModels.length, anthropicModels.length),
  );
  const maxStages = Math.max(1, Math.min(configuredMaxStages, Math.max(openaiModels.length, anthropicModels.length)));

  if (!openaiKey && !anthropicKey) {
    structuredLog("ERROR", "segment_llm_error", requestId, interaction_id, {
      error_code: "missing_all_provider_keys",
      error_class: "config_error",
      duration_ms: Date.now() - t0,
    });
    return fallbackResponse(transcriptLength, ["config_error_no_provider_api_keys"], t0);
  }

  const cascade = await runSegmentationCascade({
    prompt,
    transcript,
    transcriptLength,
    minSegmentChars: min_segment_chars,
    maxSegments: max_segments,
    openaiModels,
    anthropicModels,
    openaiKey,
    anthropicKey,
    stageTimeoutMs,
    maxStages,
    boundaryToleranceChars,
  });

  if (!cascade.candidate) {
    structuredLog("ERROR", "segment_llm_error", requestId, interaction_id, {
      error_code: "cascade_no_valid_output",
      error_class: "provider_exhausted",
      duration_ms: Date.now() - t0,
      cascade_trace: cascade.trace,
    });
    return fallbackResponse(transcriptLength, ["cascade_no_valid_output", ...cascade.warnings], t0);
  }

  const warnings = [...cascade.warnings, ...cascade.candidate.warnings];
  let segments = cascade.candidate.segments;

  if (transcriptLength > 2000 && segments.length === 1) {
    const numFallbackSegments = transcriptLength < 5000 ? 2 : transcriptLength < 10000 ? 3 : 4;
    const segmentSize = Math.floor(transcriptLength / numFallbackSegments);
    const fallbackSegments: Segment[] = [];
    for (let i = 0; i < numFallbackSegments; i++) {
      const charStart = i * segmentSize;
      const charEnd = i === numFallbackSegments - 1 ? transcriptLength : (i + 1) * segmentSize;
      fallbackSegments.push({
        span_index: i,
        char_start: charStart,
        char_end: charEnd,
        boundary_reason: "deterministic_fallback_split",
        confidence: 0.5,
        boundary_quote: null,
      });
    }
    segments = fallbackSegments;
    warnings.push("deterministic_fallback_split");
    warnings.push(`fallback_split_${numFallbackSegments}_segments`);
  }

  const durationMs = Date.now() - t0;
  console.log(
    `[segment-llm] Produced ${segments.length} segments (provider=${cascade.candidate.provider}, model=${cascade.candidate.model}, stage=${cascade.candidate.stage})`,
  );

  structuredLog("INFO", "segment_llm_response", requestId, interaction_id, {
    segments_returned: segments.length,
    duration_ms: durationMs,
    deterministic_fallback: warnings.includes("deterministic_fallback_split"),
    cascade_winner_provider: cascade.candidate.provider,
    cascade_winner_model: cascade.candidate.model,
    cascade_winner_stage: cascade.candidate.stage,
  });

  return new Response(
    JSON.stringify({
      ok: true,
      segmenter_version: SEGMENT_LLM_VERSION,
      segments,
      warnings,
      ms: durationMs,
    } as SegmentLLMOutput),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});

// ============================================================
// FALLBACK: Return single full-call segment
// ============================================================
function fallbackResponse(
  transcriptLength: number,
  warnings: string[],
  t0: number,
): Response {
  console.log(`[segment-llm] Fallback: ${warnings.join(", ")}`);
  return new Response(
    JSON.stringify({
      ok: true,
      segmenter_version: "fallback_trivial_v1",
      segments: [
        {
          span_index: 0,
          char_start: 0,
          char_end: transcriptLength,
          boundary_reason: "fallback_full_call",
          confidence: 1.0,
          boundary_quote: null,
        },
      ],
      warnings: ["llm_failed_fallback", ...warnings],
      ms: Date.now() - t0,
    } as SegmentLLMOutput),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}
