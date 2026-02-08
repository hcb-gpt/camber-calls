/**
 * segment-llm Edge Function v1.0.0
 * LLM-powered call segmenter: identifies project-switch boundaries in transcripts
 *
 * @version 1.0.0
 * @date 2026-01-31
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

const SEGMENT_LLM_VERSION = "segment-llm_v1.2.0";

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

  // ============================================================
  // LLM CALL (OpenAI)
  // ============================================================
  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiKey) {
    console.error("[segment-llm] OPENAI_API_KEY not configured");
    return fallbackResponse(transcriptLength, ["config_error_no_api_key"], t0);
  }

  const prompt = SEGMENTATION_PROMPT
    .replace("{TRANSCRIPT}", transcript)
    .replace("{MIN_CHARS}", String(min_segment_chars))
    .replace("{MAX_SEGMENTS}", String(max_segments));

  let llmResponse: any;
  try {
    const resp = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        max_tokens: 1024,
        messages: [
          {
            role: "user",
            content: prompt,
          },
        ],
      }),
    });

    if (!resp.ok) {
      const errText = await resp.text();
      console.error(`[segment-llm] LLM API error: ${resp.status} ${errText}`);
      // Structured log: segment_llm_error
      structuredLog("ERROR", "segment_llm_error", requestId, interaction_id, {
        error_code: `llm_api_${resp.status}`,
        error_class: "openai_http_error",
        duration_ms: Date.now() - t0,
      });
      return fallbackResponse(transcriptLength, [`llm_api_error_${resp.status}`], t0);
    }

    llmResponse = await resp.json();
  } catch (fetchErr: any) {
    console.error(`[segment-llm] LLM fetch error: ${fetchErr.message}`);
    // Structured log: segment_llm_error
    structuredLog("ERROR", "segment_llm_error", requestId, interaction_id, {
      error_code: "llm_fetch_error",
      error_class: fetchErr.message || "unknown",
      duration_ms: Date.now() - t0,
    });
    return fallbackResponse(transcriptLength, [`llm_fetch_error`], t0);
  }

  // ============================================================
  // PARSE LLM OUTPUT (OpenAI format)
  // ============================================================
  let rawContent = "";
  try {
    rawContent = llmResponse.choices?.[0]?.message?.content || "";
    // Strip markdown code fences if present
    rawContent = rawContent.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
  } catch {
    console.error("[segment-llm] Failed to extract LLM text");
    return fallbackResponse(transcriptLength, ["llm_parse_error_extract"], t0);
  }

  let parsed: { segments?: Segment[] };
  try {
    parsed = JSON.parse(rawContent);
  } catch (_parseErr) {
    console.error(`[segment-llm] JSON parse failed: ${rawContent.slice(0, 200)}`);
    return fallbackResponse(transcriptLength, ["llm_parse_error_json"], t0);
  }

  if (!Array.isArray(parsed.segments) || parsed.segments.length === 0) {
    console.error("[segment-llm] No segments array in LLM output");
    return fallbackResponse(transcriptLength, ["llm_output_invalid_no_segments"], t0);
  }

  // ============================================================
  // GUARDRAILS: Validate and fix segments
  // ============================================================
  const warnings: string[] = [];
  let segments = parsed.segments;

  // 1. Clamp boundaries to [0, transcriptLength]
  segments = segments.map((seg) => ({
    ...seg,
    char_start: Math.max(0, Math.min(seg.char_start, transcriptLength)),
    char_end: Math.max(0, Math.min(seg.char_end, transcriptLength)),
  }));

  // 2. Sort by char_start and fix span_index
  segments.sort((a, b) => a.char_start - b.char_start);
  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  // 3. Make contiguous (no gaps, no overlaps)
  for (let i = 1; i < segments.length; i++) {
    if (segments[i].char_start !== segments[i - 1].char_end) {
      warnings.push(`gap_fixed_at_index_${i}`);
      segments[i].char_start = segments[i - 1].char_end;
    }
  }

  // 4. Ensure first starts at 0, last ends at transcriptLength
  if (segments[0].char_start !== 0) {
    warnings.push("first_segment_start_fixed");
    segments[0].char_start = 0;
  }
  if (segments[segments.length - 1].char_end !== transcriptLength) {
    warnings.push("last_segment_end_fixed");
    segments[segments.length - 1].char_end = transcriptLength;
  }

  // 5. Merge undersized segments into previous
  let merged = true;
  while (merged && segments.length > 1) {
    merged = false;
    for (let i = segments.length - 1; i >= 0; i--) {
      const size = segments[i].char_end - segments[i].char_start;
      if (size < min_segment_chars && segments.length > 1) {
        if (i > 0) {
          // Merge into previous
          segments[i - 1].char_end = segments[i].char_end;
          segments[i - 1].boundary_reason += "_merged_undersized";
          segments.splice(i, 1);
          warnings.push(`merged_undersized_segment_${i}`);
          merged = true;
          break;
        } else if (i === 0 && segments.length > 1) {
          // First segment undersized - merge with next
          segments[1].char_start = segments[0].char_start;
          segments.splice(0, 1);
          warnings.push("merged_undersized_first_segment");
          merged = true;
          break;
        }
      }
    }
  }

  // 6. Re-index after merges
  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  // 7. Enforce max_segments by merging lowest-confidence boundaries
  while (segments.length > max_segments) {
    // Find lowest confidence segment (excluding first)
    let minConfIdx = 1;
    let minConf = segments[1].confidence;
    for (let i = 2; i < segments.length; i++) {
      if (segments[i].confidence < minConf) {
        minConf = segments[i].confidence;
        minConfIdx = i;
      }
    }
    // Merge with previous
    segments[minConfIdx - 1].char_end = segments[minConfIdx].char_end;
    segments.splice(minConfIdx, 1);
    warnings.push(`merged_low_confidence_segment_${minConfIdx}`);
  }

  // 8. Final re-index
  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  // 9. Validate no zero-length segments
  segments = segments.filter((seg) => {
    if (seg.char_end <= seg.char_start) {
      warnings.push(`removed_zero_length_segment_${seg.span_index}`);
      return false;
    }
    return true;
  });

  // 10. Final re-index
  segments = segments.map((seg, idx) => ({ ...seg, span_index: idx }));

  // If all segments got filtered out, fallback
  if (segments.length === 0) {
    return fallbackResponse(transcriptLength, ["all_segments_invalid"], t0);
  }

  // ============================================================
  // RETRY LOGIC: Single span on long transcript (P0 Task)
  // ============================================================
  // If transcript > 2000 chars and LLM returned only 1 span, retry with stricter instruction
  let retriedOnce = false;
  if (transcriptLength > 2000 && segments.length === 1) {
    console.log(
      `[segment-llm] Single span on long transcript (${transcriptLength} chars) - retrying with stricter instruction`,
    );
    warnings.push("single_span_retry_attempt");
    retriedOnce = true;

    // Stricter prompt that demands at least 2 chunks
    const stricterPrompt = `You are a call transcript segmenter for a construction company.

CRITICAL REQUIREMENT: For transcripts over 2000 characters, you MUST produce AT LEAST 2 segments unless the call is genuinely single-topic with NO project switches whatsoever.

Your task: Identify boundaries where the conversation switches from one PROJECT to another.

RULES:
1. A "project" is a specific construction job (e.g., "Johnson Residence", "Smith Project", "the Hurley job")
2. For transcripts > 2000 chars: find at least ONE natural break point (topic shift, pause, speaker change on different topic)
3. If truly single-topic: return 1 segment with high confidence, but this should be rare for long calls
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
      "boundary_reason": "initial_project|topic_shift|project_switch|natural_break",
      "confidence": 0.0-1.0,
      "boundary_quote": "<exact quote <=50 chars showing the switch>"
    }
  ]
}

TRANSCRIPT:
{TRANSCRIPT}`;

    const retryPrompt = stricterPrompt
      .replace("{TRANSCRIPT}", transcript)
      .replace("{MIN_CHARS}", String(min_segment_chars))
      .replace("{MAX_SEGMENTS}", String(max_segments));

    try {
      const retryResp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${openaiKey}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          max_tokens: 1024,
          messages: [
            {
              role: "user",
              content: retryPrompt,
            },
          ],
        }),
      });

      if (retryResp.ok) {
        const retryData = await retryResp.json();
        const retryContent = (retryData.choices?.[0]?.message?.content || "")
          .replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();

        try {
          const retryParsed = JSON.parse(retryContent);
          if (Array.isArray(retryParsed.segments) && retryParsed.segments.length > 0) {
            // Re-run guardrails on retry result (simplified version)
            let retrySegments = retryParsed.segments;
            retrySegments = retrySegments.map((seg: any) => ({
              ...seg,
              char_start: Math.max(0, Math.min(seg.char_start, transcriptLength)),
              char_end: Math.max(0, Math.min(seg.char_end, transcriptLength)),
            }));
            retrySegments.sort((a: any, b: any) => a.char_start - b.char_start);
            retrySegments = retrySegments.map((seg: any, idx: number) => ({ ...seg, span_index: idx }));

            // Make contiguous
            for (let i = 1; i < retrySegments.length; i++) {
              if (retrySegments[i].char_start !== retrySegments[i - 1].char_end) {
                retrySegments[i].char_start = retrySegments[i - 1].char_end;
              }
            }
            if (retrySegments[0].char_start !== 0) retrySegments[0].char_start = 0;
            if (retrySegments[retrySegments.length - 1].char_end !== transcriptLength) {
              retrySegments[retrySegments.length - 1].char_end = transcriptLength;
            }

            // If retry gave us multiple segments, use them!
            if (retrySegments.length > 1) {
              console.log(`[segment-llm] Retry successful: ${retrySegments.length} segments`);
              segments = retrySegments;
              warnings.push("single_span_retry_successful");
            } else {
              warnings.push("single_span_retry_still_single");
            }
          }
        } catch (_retryParseErr) {
          warnings.push("single_span_retry_parse_error");
        }
      } else {
        warnings.push("single_span_retry_http_error");
      }
    } catch (_retryErr: any) {
      warnings.push("single_span_retry_fetch_error");
    }
  }

  // ============================================================
  // DETERMINISTIC FALLBACK: If still single span after retry
  // ============================================================
  if (transcriptLength > 2000 && segments.length === 1) {
    console.log(`[segment-llm] Still single span after retry - using deterministic fallback split`);
    warnings.push("deterministic_fallback_applied");

    // Split transcript into 2-4 equal segments based on length
    const numFallbackSegments = transcriptLength < 5000 ? 2 : transcriptLength < 10000 ? 3 : 4;
    const segmentSize = Math.floor(transcriptLength / numFallbackSegments);

    segments = [];
    for (let i = 0; i < numFallbackSegments; i++) {
      const charStart = i * segmentSize;
      const charEnd = i === numFallbackSegments - 1 ? transcriptLength : (i + 1) * segmentSize;
      segments.push({
        span_index: i,
        char_start: charStart,
        char_end: charEnd,
        boundary_reason: "deterministic_fallback_split",
        confidence: 0.5, // Lower confidence for fallback
        boundary_quote: null,
      });
    }

    // Mark these segments with fallback metadata flag
    // This will be added to segment_metadata in segment-call
    warnings.push(`fallback_split_${numFallbackSegments}_segments`);
  }

  // Truncate boundary_quote to 50 chars
  segments = segments.map((seg) => ({
    ...seg,
    boundary_quote: seg.boundary_quote ? seg.boundary_quote.slice(0, 50) : null,
  }));

  const durationMs = Date.now() - t0;
  console.log(`[segment-llm] Produced ${segments.length} segments with ${warnings.length} warnings`);

  // Structured log: segment_llm_response
  structuredLog("INFO", "segment_llm_response", requestId, interaction_id, {
    segments_returned: segments.length,
    duration_ms: durationMs,
    retry_attempted: retriedOnce,
    deterministic_fallback: warnings.includes("deterministic_fallback_applied"),
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
