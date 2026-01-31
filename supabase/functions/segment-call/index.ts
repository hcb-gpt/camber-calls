/**
 * segment-call Edge Function v2.1.0
 * Multi-span producer: calls segment-llm, writes N conversation_spans, then chains each span to
 * context-assembly → ai-router.
 *
 * Sprint-0 invariants:
 * - Reseed rule: if ANY span_attributions exist for this interaction, do NOT resegment (409 + error_code).
 * - Fail closed: if any required downstream step fails, return 500 + error_code=chain_failed.
 * - Downstream auth uses X-Edge-Secret (never service-role bearer).
 *
 * Auth (internal gate; verify_jwt=false):
 * - X-Edge-Secret + provenance allowlist, OR
 * - JWT + ALLOWED_EMAILS verified via auth.getUser() (debug path)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGMENT_CALL_VERSION = "v2.1.0";

const ALLOWED_PROVENANCE_SOURCES = [
  "process-call",
  "zapier",
  "pipedream",
  "n8n",
  "edge",
  "test",
];

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SEGMENT_LLM_URL = `${SUPABASE_URL}/functions/v1/segment-llm`;
const CONTEXT_ASSEMBLY_URL = `${SUPABASE_URL}/functions/v1/context-assembly`;
const AI_ROUTER_URL = `${SUPABASE_URL}/functions/v1/ai-router`;

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
};

const jsonHeaders = { "Content-Type": "application/json" };

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
    return new Response(JSON.stringify({
      ok: false,
      error: "invalid_json",
      error_code: "bad_request",
      version: SEGMENT_CALL_VERSION,
    }), { status: 400, headers: jsonHeaders });
  }

  const provenanceSource = body.source || "unknown";

  const hasValidEdgeSecret =
    expectedSecret &&
    edgeSecretHeader === expectedSecret &&
    ALLOWED_PROVENANCE_SOURCES.includes(provenanceSource);

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
    return new Response(JSON.stringify({
      ok: false,
      error: "unauthorized",
      error_code: "auth_failed",
      hint: "Requires X-Edge-Secret with allowlisted source OR JWT with allowed email",
      version: SEGMENT_CALL_VERSION,
    }), { status: 401, headers: jsonHeaders });
  }

  const {
    interaction_id,
    transcript,
    dry_run = false,
    max_segments = 10,
    min_segment_chars = 200,
  } = body;

  if (!interaction_id) {
    return new Response(JSON.stringify({
      ok: false,
      error: "missing_interaction_id",
      error_code: "bad_request",
      version: SEGMENT_CALL_VERSION,
    }), { status: 400, headers: jsonHeaders });
  }

  const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!edgeSecret) {
    return new Response(JSON.stringify({
      ok: false,
      error: "config_error",
      error_code: "config_missing",
      hint: "EDGE_SHARED_SECRET not set",
      version: SEGMENT_CALL_VERSION,
    }), { status: 500, headers: jsonHeaders });
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
      return new Response(JSON.stringify({
        ok: false,
        error: "transcript_not_found",
        error_code: "no_transcript",
        interaction_id,
        version: SEGMENT_CALL_VERSION,
      }), { status: 400, headers: jsonHeaders });
    }

    spanTranscript = callsRaw.transcript;
  }

  // ============================================================
  // 2) RESEED RULE (409 IF ANY ATTRIBUTIONS EXIST)
  // ============================================================
  const { data: existingSpans, error: spansErr } = await db
    .from("conversation_spans")
    .select("id")
    .eq("interaction_id", interaction_id);

  if (spansErr) {
    return new Response(JSON.stringify({
      ok: false,
      error: "db_error",
      error_code: "db_error",
      detail: spansErr.message,
      version: SEGMENT_CALL_VERSION,
    }), { status: 500, headers: jsonHeaders });
  }

  if (existingSpans && existingSpans.length > 0) {
    const existingSpanIds = existingSpans.map((s: any) => s.id);
    const { data: existingAttribs, error: attribErr } = await db
      .from("span_attributions")
      .select("id")
      .in("span_id", existingSpanIds)
      .limit(1);

    if (attribErr) {
      return new Response(JSON.stringify({
        ok: false,
        error: "db_error",
        error_code: "db_error",
        detail: attribErr.message,
        version: SEGMENT_CALL_VERSION,
      }), { status: 500, headers: jsonHeaders });
    }

    if (existingAttribs && existingAttribs.length > 0) {
      return new Response(JSON.stringify({
        ok: false,
        error: "already_attributed",
        error_code: "already_attributed",
        interaction_id,
        version: SEGMENT_CALL_VERSION,
      }), { status: 409, headers: jsonHeaders });
    }
  }

  // ============================================================
  // 3) CALL segment-llm FOR SEGMENTATION (FAIL-SAFE FALLBACK)
  // ============================================================
  let segments: SegmentFromLLM[] = [];
  let segmenterVersion = "fallback_trivial_v1";
  const segmenterWarnings: string[] = [];

  try {
    const llmResp = await fetch(SEGMENT_LLM_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Edge-Secret": edgeSecret,
      },
      body: JSON.stringify({
        interaction_id,
        transcript: spanTranscript,
        source: "segment-call",
        max_segments,
        min_segment_chars,
      }),
    });

    if (!llmResp.ok) {
      segmenterWarnings.push(`segment_llm_http_${llmResp.status}`);
      segments = [{
        span_index: 0,
        char_start: 0,
        char_end: spanTranscript.length,
        boundary_reason: "fallback_segment_llm_http_error",
        confidence: 1.0,
        boundary_quote: null,
      }];
    } else {
      const llmData = await llmResp.json();
      if (llmData?.ok && Array.isArray(llmData.segments) && llmData.segments.length > 0) {
        segments = llmData.segments;
        segmenterVersion = llmData.segmenter_version || "segment-llm_v1.0.0";
        if (Array.isArray(llmData.warnings)) segmenterWarnings.push(...llmData.warnings);
      } else {
        segmenterWarnings.push("segment_llm_invalid_response");
        segments = [{
          span_index: 0,
          char_start: 0,
          char_end: spanTranscript.length,
          boundary_reason: "fallback_segment_llm_invalid",
          confidence: 1.0,
          boundary_quote: null,
        }];
      }
    }
  } catch (e: any) {
    segmenterWarnings.push(`segment_llm_fetch_error:${e?.message || "unknown"}`);
    segments = [{
      span_index: 0,
      char_start: 0,
      char_end: spanTranscript.length,
      boundary_reason: "fallback_segment_llm_fetch_error",
      confidence: 1.0,
      boundary_quote: null,
    }];
  }

  // ============================================================
  // 4) REBUILD SPANS (SAFE: NO ATTRIBUTIONS)
  // ============================================================
  if (existingSpans && existingSpans.length > 0) {
    const { error: deleteErr } = await db
      .from("conversation_spans")
      .delete()
      .eq("interaction_id", interaction_id);

    if (deleteErr) {
      return new Response(JSON.stringify({
        ok: false,
        error: "span_delete_failed",
        error_code: "db_error",
        detail: deleteErr.message,
        version: SEGMENT_CALL_VERSION,
      }), { status: 500, headers: jsonHeaders });
    }
  }

  const now = new Date().toISOString();
  const spanRowsWithMetadata = segments.map((seg) => {
    const segmentText = spanTranscript!.slice(seg.char_start, seg.char_end);
    const wordCount = segmentText.split(/\s+/).filter(Boolean).length;
    return {
      interaction_id,
      span_index: seg.span_index,
      char_start: seg.char_start,
      char_end: seg.char_end,
      transcript_segment: segmentText,
      word_count: wordCount,
      segmenter_version: segmenterVersion,
      segment_reason: seg.boundary_reason,
      segment_metadata: {
        confidence: seg.confidence,
        boundary_quote: seg.boundary_quote,
      },
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
      return new Response(JSON.stringify({
        ok: false,
        error: "span_creation_failed",
        error_code: "db_error",
        detail: ins1.error.message,
        version: SEGMENT_CALL_VERSION,
        spans_written,
        spans_write_ok,
      }), { status: 500, headers: jsonHeaders });
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
      return new Response(JSON.stringify({
        ok: false,
        error: "span_creation_failed",
        error_code: "db_error",
        detail: ins2.error.message,
        version: SEGMENT_CALL_VERSION,
        spans_written,
        spans_write_ok,
      }), { status: 500, headers: jsonHeaders });
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
    return new Response(JSON.stringify({
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
    }), { status: 500, headers: jsonHeaders });
  }

  return new Response(JSON.stringify({
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
    dry_run,
    ms: Date.now() - t0,
  }), { status: 200, headers: jsonHeaders });
});
