/**
 * segment-call Edge Function v2.5.2
 * Multi-span producer: calls segment-llm, writes N conversation_spans, then chains each span to
 * context-assembly → ai-router.
 *
 * Sprint-0 invariants:
 * - Reseed rule: if ANY span_attributions exist for this interaction, do NOT resegment (409 + error_code).
 * - Fail closed: if any required downstream step fails, return 500 + error_code=chain_failed.
 * - Downstream auth uses X-Edge-Secret (never service-role bearer).
 *
 * Auth (internal gate; verify_jwt=false):
 * - X-Edge-Secret == EDGE_SHARED_SECRET, OR
 * - JWT + ALLOWED_EMAILS verified via auth.getUser() (debug path)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGMENT_CALL_VERSION = "v2.5.2";
const MAX_SEGMENT_CHARS_HARD_LIMIT = 3000;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SEGMENT_LLM_URL = `${SUPABASE_URL}/functions/v1/segment-llm`;
const CONTEXT_ASSEMBLY_URL = `${SUPABASE_URL}/functions/v1/context-assembly`;
const AI_ROUTER_URL = `${SUPABASE_URL}/functions/v1/ai-router`;
const STRIKING_DETECT_URL = `${SUPABASE_URL}/functions/v1/striking-detect`;
const JOURNAL_EXTRACT_URL = `${SUPABASE_URL}/functions/v1/journal-extract`;
const GENERATE_SUMMARY_URL = `${SUPABASE_URL}/functions/v1/generate-summary`;

type SegmentFromLLM = {
  span_index: number;
  char_start: number;
  char_end: number;
  boundary_reason: string;
  confidence: number;
  boundary_quote: string | null;
};

type SpanChainStatus = {
  span_id: string;
  span_index: number;
  context_assembly_status: number | null;
  ai_router_status: number | null;
  error_code: string | null;
  error_detail: string | null;
  // v2.4.0: async post-attribution hooks
  striking_detect_fired: boolean;
  journal_extract_fired: boolean;
};

const jsonHeaders = { "Content-Type": "application/json" };

type TranscriptSanitizeResult = {
  text: string;
  replaced: number;
};

function sanitizeTranscriptForPipeline(text: string): TranscriptSanitizeResult {
  let replaced = 0;
  // deno-lint-ignore no-control-regex -- intentional: scrub control chars before JSON packaging/prompting
  const sanitized = String(text || "").replace(/[\x00-\x1F\x7F]/g, () => {
    replaced += 1;
    return " ";
  });
  return { text: sanitized, replaced };
}

function deterministicSegmentsForLength(
  transcriptLength: number,
  maxSegmentChars: number,
  boundaryReason: string,
): SegmentFromLLM[] {
  if (transcriptLength <= 0) {
    return [{
      span_index: 0,
      char_start: 0,
      char_end: 0,
      boundary_reason: boundaryReason,
      confidence: 1,
      boundary_quote: null,
    }];
  }

  const chunkCount = Math.max(1, Math.ceil(transcriptLength / Math.max(1, maxSegmentChars)));
  const segments: SegmentFromLLM[] = [];
  for (let i = 0; i < chunkCount; i++) {
    const charStart = Math.floor((transcriptLength * i) / chunkCount);
    const charEnd = Math.floor((transcriptLength * (i + 1)) / chunkCount);
    segments.push({
      span_index: i,
      char_start: charStart,
      char_end: charEnd,
      boundary_reason: boundaryReason,
      confidence: 0.5,
      boundary_quote: null,
    });
  }
  return segments;
}

function enforceMaxSegmentChars(
  inputSegments: SegmentFromLLM[],
  maxSegmentChars: number,
  warnings: string[],
): SegmentFromLLM[] {
  const rebuilt: SegmentFromLLM[] = [];

  for (const seg of inputSegments) {
    const segLen = Math.max(0, seg.char_end - seg.char_start);
    if (segLen <= maxSegmentChars || segLen === 0) {
      rebuilt.push(seg);
      continue;
    }

    const chunkCount = Math.ceil(segLen / maxSegmentChars);
    warnings.push(`segment_call_split_oversize_${seg.span_index}_into_${chunkCount}`);
    for (let i = 0; i < chunkCount; i++) {
      const charStart = seg.char_start + Math.floor((segLen * i) / chunkCount);
      const charEnd = seg.char_start + Math.floor((segLen * (i + 1)) / chunkCount);
      rebuilt.push({
        span_index: 0,
        char_start: charStart,
        char_end: charEnd,
        boundary_reason: `${seg.boundary_reason}_segment_call_split`,
        confidence: seg.confidence,
        boundary_quote: i === 0 ? seg.boundary_quote : null,
      });
    }
  }

  return rebuilt.map((seg, idx) => ({ ...seg, span_index: idx }));
}

async function logDiagnostic(
  message: string,
  metadata: Record<string, unknown>,
  logLevel = "error",
): Promise<void> {
  try {
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) return;
    const sb = createClient(SUPABASE_URL, serviceRoleKey);
    await sb.from("diagnostic_logs").insert({
      function_name: "segment-call",
      function_version: SEGMENT_CALL_VERSION,
      log_level: logLevel,
      message,
      metadata,
    });
  } catch (e) {
    console.warn(`[segment-call] diagnostic_logs insert failed: ${(e as Error)?.message || e}`);
  }
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  // ============================================================
  // INTERNAL AUTH GATE (verify_jwt: false - auth handled here)
  // ============================================================
  const edgeSecretHeader = req.headers.get("X-Edge-Secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");
  const authHeader = req.headers.get("Authorization");

  let body: any;
  try {
    body = await req.json();
  } catch {
    await logDiagnostic("INPUT_INVALID", { reason: "invalid_json_body" }, "warning");
    return new Response(
      JSON.stringify({
        ok: false,
        error: "invalid_json",
        error_code: "bad_request",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const hasValidEdgeSecret = expectedSecret &&
    edgeSecretHeader === expectedSecret;

  let hasValidJwt = false;
  if (!hasValidEdgeSecret && authHeader?.startsWith("Bearer ")) {
    const anonClient = createClient(
      SUPABASE_URL,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: authErr } = await anonClient.auth.getUser();
    if (!authErr && user?.email) {
      const allowedEmails = (Deno.env.get("ALLOWED_EMAILS") || "")
        .split(",")
        .map((e) => e.trim().toLowerCase())
        .filter(Boolean);
      hasValidJwt = allowedEmails.includes(user.email.toLowerCase());
    }
  }

  if (!hasValidEdgeSecret && !hasValidJwt) {
    await logDiagnostic("AUTH_FAILED", {
      reason: "edge_secret_or_allowed_jwt_required",
      edge_secret_present: Boolean(edgeSecretHeader),
      auth_header_present: Boolean(authHeader),
      allowed_jwt: hasValidJwt,
    });
    return new Response(
      JSON.stringify({
        ok: false,
        error: "unauthorized",
        error_code: "auth_failed",
        hint: "Requires X-Edge-Secret matching EDGE_SHARED_SECRET OR JWT with allowed email",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 401, headers: jsonHeaders },
    );
  }

  const {
    interaction_id,
    transcript,
    dry_run = false,
    max_segments = 10,
    min_segment_chars = 200,
  } = body;

  if (!interaction_id) {
    await logDiagnostic("INPUT_INVALID", { reason: "missing_interaction_id" }, "warning");
    return new Response(
      JSON.stringify({
        ok: false,
        error: "missing_interaction_id",
        error_code: "bad_request",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!edgeSecret) {
    await logDiagnostic("AUTH_FAILED", {
      reason: "edge_shared_secret_missing",
    });
    return new Response(
      JSON.stringify({
        ok: false,
        error: "config_error",
        error_code: "config_missing",
        hint: "EDGE_SHARED_SECRET not set",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const db = createClient(
    SUPABASE_URL,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let spans_written = false;
  let spans_write_ok = false;

  // ============================================================
  // 1) FETCH TRANSCRIPT
  // ============================================================
  let spanTranscript: string | null = typeof transcript === "string" ? transcript : null;

  if (!spanTranscript) {
    const { data: callsRaw, error: fetchErr } = await db
      .from("calls_raw")
      .select("transcript")
      .eq("interaction_id", interaction_id)
      .single();

    if (fetchErr || !callsRaw?.transcript) {
      await logDiagnostic("INPUT_INVALID", {
        reason: "transcript_not_found",
        interaction_id,
      }, "warning");
      return new Response(
        JSON.stringify({
          ok: false,
          error: "transcript_not_found",
          error_code: "no_transcript",
          interaction_id,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 400, headers: jsonHeaders },
      );
    }

    spanTranscript = callsRaw.transcript;
  }

  const transcriptSanitize = sanitizeTranscriptForPipeline(spanTranscript || "");
  spanTranscript = transcriptSanitize.text;
  const transcriptControlCharsSanitized = transcriptSanitize.replaced;

  // ============================================================
  // 2) RESEED RULE (409 IF ANY ATTRIBUTIONS EXIST ON ACTIVE SPANS)
  // ============================================================
  const { data: existingSpans, error: spansErr } = await db
    .from("conversation_spans")
    .select("id")
    .eq("interaction_id", interaction_id)
    .eq("is_superseded", false);

  if (spansErr) {
    await logDiagnostic("DB_WRITE_FAILED", {
      reason: "conversation_spans_query_failed",
      interaction_id,
      detail: spansErr.message,
    });
    return new Response(
      JSON.stringify({
        ok: false,
        error: "db_error",
        error_code: "db_error",
        detail: spansErr.message,
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 500, headers: jsonHeaders },
    );
  }

  if (existingSpans && existingSpans.length > 0) {
    const existingSpanIds = existingSpans.map((s: any) => s.id);
    const { data: existingAttribs, error: attribErr } = await db
      .from("span_attributions")
      .select("id")
      .in("span_id", existingSpanIds)
      .limit(1);

    if (attribErr) {
      await logDiagnostic("DB_WRITE_FAILED", {
        reason: "span_attributions_query_failed",
        interaction_id,
        detail: attribErr.message,
      });
      return new Response(
        JSON.stringify({
          ok: false,
          error: "db_error",
          error_code: "db_error",
          detail: attribErr.message,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (existingAttribs && existingAttribs.length > 0) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "already_attributed",
          error_code: "already_attributed",
          interaction_id,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 409, headers: jsonHeaders },
      );
    }
  }

  // ============================================================
  // 3) CALL segment-llm FOR SEGMENTATION (FAIL-SAFE FALLBACK)
  // ============================================================
  let segments: SegmentFromLLM[] = [];
  let segmenterVersion = "fallback_trivial_v1";
  const segmenterWarnings: string[] = [];
  if (transcriptControlCharsSanitized > 0) {
    segmenterWarnings.push(`transcript_control_chars_sanitized_${transcriptControlCharsSanitized}`);
  }

  try {
    const llmResp = await fetch(SEGMENT_LLM_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Edge-Secret": edgeSecret,
        // No Authorization header - segment-llm uses X-Edge-Secret only
      },
      body: JSON.stringify({
        interaction_id,
        transcript: spanTranscript,
        source: "segment-call",
        max_segments,
        min_segment_chars,
        max_segment_chars: MAX_SEGMENT_CHARS_HARD_LIMIT,
      }),
    });

    if (!llmResp.ok) {
      segmenterWarnings.push(`segment_llm_http_${llmResp.status}`);
      segments = deterministicSegmentsForLength(
        spanTranscript.length,
        MAX_SEGMENT_CHARS_HARD_LIMIT,
        "fallback_segment_llm_http_error",
      );
    } else {
      const llmData = await llmResp.json();
      if (llmData?.ok && Array.isArray(llmData.segments) && llmData.segments.length > 0) {
        segments = llmData.segments;
        segmenterVersion = llmData.segmenter_version || "segment-llm_v1.0.0";
        if (Array.isArray(llmData.warnings)) segmenterWarnings.push(...llmData.warnings);
      } else {
        segmenterWarnings.push("segment_llm_invalid_response");
        segments = deterministicSegmentsForLength(
          spanTranscript.length,
          MAX_SEGMENT_CHARS_HARD_LIMIT,
          "fallback_segment_llm_invalid",
        );
      }
    }
  } catch (e: any) {
    segmenterWarnings.push(`segment_llm_fetch_error:${e?.message || "unknown"}`);
    segments = deterministicSegmentsForLength(
      spanTranscript.length,
      MAX_SEGMENT_CHARS_HARD_LIMIT,
      "fallback_segment_llm_fetch_error",
    );
  }
  segments = enforceMaxSegmentChars(segments, MAX_SEGMENT_CHARS_HARD_LIMIT, segmenterWarnings);

  // ============================================================
  // 4) REBUILD SPANS (SAFE: NO ATTRIBUTIONS ON ACTIVE SPANS)
  // ============================================================
  if (existingSpans && existingSpans.length > 0) {
    // Delete only active (non-superseded) spans
    const { error: deleteErr } = await db
      .from("conversation_spans")
      .delete()
      .eq("interaction_id", interaction_id)
      .eq("is_superseded", false);

    if (deleteErr) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "span_delete_failed",
          error_code: "db_error",
          detail: deleteErr.message,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 500, headers: jsonHeaders },
      );
    }
  }

  const now = new Date().toISOString();
  const isDeterministicFallback = segmenterWarnings.includes("deterministic_fallback_applied");
  const spanRowsWithMetadata = segments.map((seg) => {
    const segmentText = spanTranscript!.slice(seg.char_start, seg.char_end);
    const wordCount = segmentText.split(/\s+/).filter(Boolean).length;
    const metadata: Record<string, any> = {
      confidence: seg.confidence,
      boundary_quote: seg.boundary_quote,
    };
    // Mark segments created by deterministic fallback
    if (isDeterministicFallback) {
      metadata.fallback = true;
    }
    return {
      interaction_id,
      span_index: seg.span_index,
      char_start: seg.char_start,
      char_end: seg.char_end,
      transcript_segment: segmentText,
      word_count: wordCount,
      segmenter_version: segmenterVersion,
      segment_reason: seg.boundary_reason,
      segment_metadata: metadata,
      is_superseded: false,
      segment_generation: 1,
      created_at: now,
    };
  });

  spans_written = true;

  // insert attempt #1 (with segment_metadata)
  let insertedSpans: { id: string; span_index: number }[] = [];
  const ins1 = await db
    .from("conversation_spans")
    .insert(spanRowsWithMetadata)
    .select("id, span_index");

  if (ins1.error) {
    const msg = (ins1.error.message || "").toLowerCase();
    const missingMetaCol = msg.includes("segment_metadata") && msg.includes("does not exist");
    if (!missingMetaCol) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "span_creation_failed",
          error_code: "db_error",
          detail: ins1.error.message,
          version: SEGMENT_CALL_VERSION,
          spans_written,
          spans_write_ok,
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    // retry without segment_metadata (migration is optional)
    segmenterWarnings.push("segment_metadata_column_missing");
    const rowsNoMeta = spanRowsWithMetadata.map((r: any) => {
      const { segment_metadata: _omit, ...rest } = r;
      return rest;
    });

    const ins2 = await db
      .from("conversation_spans")
      .insert(rowsNoMeta)
      .select("id, span_index");

    if (ins2.error) {
      return new Response(
        JSON.stringify({
          ok: false,
          error: "span_creation_failed",
          error_code: "db_error",
          detail: ins2.error.message,
          version: SEGMENT_CALL_VERSION,
          spans_written,
          spans_write_ok,
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    insertedSpans = (ins2.data || []) as any;
  } else {
    insertedSpans = (ins1.data || []) as any;
  }

  insertedSpans.sort((a, b) => a.span_index - b.span_index);

  const spanIds = insertedSpans.map((s) => s.id);
  const spanCount = insertedSpans.length;

  spans_write_ok = true;

  // ============================================================
  // 5) PER-SPAN CHAIN: context-assembly → ai-router
  // ============================================================
  const chainStatuses: SpanChainStatus[] = [];

  for (const span of insertedSpans) {
    const status: SpanChainStatus = {
      span_id: span.id,
      span_index: span.span_index,
      context_assembly_status: null,
      ai_router_status: null,
      error_code: null,
      error_detail: null,
      striking_detect_fired: false,
      journal_extract_fired: false,
    };

    // context-assembly
    let contextData: any = null;
    try {
      const ctxResp = await fetch(CONTEXT_ASSEMBLY_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Edge-Secret": edgeSecret,
        },
        body: JSON.stringify({
          span_id: span.id,
          interaction_id,
          source: "segment-call",
        }),
      });

      status.context_assembly_status = ctxResp.status;
      if (!ctxResp.ok) {
        status.error_code = "context_assembly_failed";
        status.error_detail = await ctxResp.text();
        chainStatuses.push(status);
        continue;
      }

      contextData = await ctxResp.json();
    } catch (e: any) {
      status.error_code = "context_assembly_exception";
      status.error_detail = e?.message || "unknown";
      chainStatuses.push(status);
      continue;
    }

    if (!contextData?.context_package) {
      status.error_code = "no_context_package";
      status.error_detail = "context-assembly returned no context_package";
      chainStatuses.push(status);
      continue;
    }

    // ai-router
    try {
      const routerResp = await fetch(AI_ROUTER_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Edge-Secret": edgeSecret,
        },
        body: JSON.stringify({
          context_package: contextData.context_package,
          dry_run,
          source: "segment-call",
        }),
      });

      status.ai_router_status = routerResp.status;
      if (!routerResp.ok) {
        status.error_code = "ai_router_failed";
        status.error_detail = await routerResp.text();
        chainStatuses.push(status);
        continue;
      }

      // ============================================================
      // v2.4.0: ASYNC POST-ATTRIBUTION HOOKS (fire-and-forget)
      // These are supplementary — failures do NOT block the pipeline.
      // ============================================================
      let routerData: any = null;
      try {
        routerData = await routerResp.json();
      } catch {
        // If we can't parse router response, skip hooks but don't fail
      }

      // HOOK 1: striking-detect (runs on every span)
      try {
        fetch(STRIKING_DETECT_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Edge-Secret": edgeSecret,
          },
          body: JSON.stringify({
            span_id: span.id,
            interaction_id,
            source: "segment-call",
          }),
        }).catch((e: any) => {
          console.error(`[segment-call] striking-detect fire-and-forget error: ${e?.message}`);
          void logDiagnostic("DOWNSTREAM_CALL_FAILED", {
            hook: "striking-detect",
            interaction_id,
            span_id: span.id,
            error: e?.message || "unknown",
          });
        });
        status.striking_detect_fired = true;
      } catch {
        await logDiagnostic("DOWNSTREAM_CALL_FAILED", {
          hook: "striking-detect",
          interaction_id,
          span_id: span.id,
          error: "dispatch_exception",
        });
        // Non-fatal
      }

      // HOOK 2: journal-extract (only when attribution assigned a project)
      const appliedProjectId = routerData?.gatekeeper?.applied_project_id;
      const routerDecision = routerData?.decision;
      if (routerDecision === "assign" && appliedProjectId) {
        try {
          fetch(JOURNAL_EXTRACT_URL, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Edge-Secret": edgeSecret,
            },
            body: JSON.stringify({
              span_id: span.id,
              interaction_id,
              project_id: appliedProjectId,
              source: "segment-call",
            }),
          }).catch((e: any) => {
            console.error(`[segment-call] journal-extract fire-and-forget error: ${e?.message}`);
            void logDiagnostic("DOWNSTREAM_CALL_FAILED", {
              hook: "journal-extract",
              interaction_id,
              span_id: span.id,
              project_id: appliedProjectId,
              error: e?.message || "unknown",
            });
          });
          status.journal_extract_fired = true;
        } catch {
          await logDiagnostic("DOWNSTREAM_CALL_FAILED", {
            hook: "journal-extract",
            interaction_id,
            span_id: span.id,
            project_id: appliedProjectId,
            error: "dispatch_exception",
          });
          // Non-fatal
        }
      }
    } catch (e: any) {
      status.error_code = "ai_router_exception";
      status.error_detail = e?.message || "unknown";
      chainStatuses.push(status);
      continue;
    }

    chainStatuses.push(status);
  }

  const allSuccess = chainStatuses.every((s) =>
    s.context_assembly_status === 200 &&
    s.ai_router_status === 200 &&
    !s.error_code
  );

  if (!allSuccess) {
    await logDiagnostic("DOWNSTREAM_CALL_FAILED", {
      reason: "chain_failed",
      interaction_id,
      failed_count: chainStatuses.filter((s) => Boolean(s.error_code)).length,
      sample_failures: chainStatuses
        .filter((s) => Boolean(s.error_code))
        .slice(0, 5)
        .map((s) => ({
          span_id: s.span_id,
          span_index: s.span_index,
          context_assembly_status: s.context_assembly_status,
          ai_router_status: s.ai_router_status,
          error_code: s.error_code,
        })),
    });
    return new Response(
      JSON.stringify({
        ok: false,
        error: "chain_failed",
        error_code: "chain_failed",
        version: SEGMENT_CALL_VERSION,
        interaction_id,
        spans_written,
        spans_write_ok,
        span_ids: spanIds,
        span_count: spanCount,
        segmenter_version: segmenterVersion,
        segmenter_warnings: segmenterWarnings,
        chain: {
          attempted: true,
          auth_mode: "X-Edge-Secret",
          statuses: chainStatuses,
        },
        dry_run,
        ms: Date.now() - t0,
      }),
      { status: 500, headers: jsonHeaders },
    );
  }

  // ============================================================
  // v2.5.0: CALL-LEVEL SUMMARY HOOK (fire-and-forget)
  // Trigger once after all spans finish context-assembly + ai-router.
  // ============================================================
  let generateSummaryFired = false;
  if (!dry_run) {
    try {
      fetch(GENERATE_SUMMARY_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Edge-Secret": edgeSecret,
        },
        body: JSON.stringify({
          interaction_id,
          source: "segment-call",
        }),
      }).catch((e: any) => {
        console.error(`[segment-call] generate-summary fire-and-forget error: ${e?.message}`);
        void logDiagnostic("DOWNSTREAM_CALL_FAILED", {
          hook: "generate-summary",
          interaction_id,
          error: e?.message || "unknown",
        });
      });
      generateSummaryFired = true;
    } catch {
      await logDiagnostic("DOWNSTREAM_CALL_FAILED", {
        hook: "generate-summary",
        interaction_id,
        error: "dispatch_exception",
      });
      // Non-fatal
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      version: SEGMENT_CALL_VERSION,
      interaction_id,
      spans_written,
      spans_write_ok,
      span_ids: spanIds,
      span_count: spanCount,
      segmenter_version: segmenterVersion,
      segmenter_warnings: segmenterWarnings,
      chain: {
        attempted: true,
        auth_mode: "X-Edge-Secret",
        statuses: chainStatuses,
      },
      post_hooks: {
        generate_summary_fired: generateSummaryFired,
      },
      dry_run,
      ms: Date.now() - t0,
    }),
    { status: 200, headers: jsonHeaders },
  );
});
