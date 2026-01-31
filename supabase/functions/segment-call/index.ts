/**
 * segment-call Edge Function v2.0.0
 * Span producer: segments calls into N conversation spans via segment-llm,
 * then chains each span to context-assembly → ai-router
 *
 * @version 2.0.0
 * @date 2026-01-31
 * @purpose v4 multi-project segmentation + N-span attribution chain
 *
 * CHANGES from v1.4.0:
 * - Calls segment-llm for LLM-powered segmentation
 * - Creates N spans (not just 1)
 * - Loops spans → context-assembly → ai-router
 * - Reseed rule: 409 if span_attributions exist for this interaction
 * - Response includes span_ids[], span_count, per-span chain statuses
 *
 * Auth: X-Edge-Secret + provenance OR JWT + ALLOWED_EMAILS
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGMENT_CALL_VERSION = "v2.0.0";

// ============================================================
// AUTH CONFIGURATION
// ============================================================
const ALLOWED_PROVENANCE_SOURCES = [
  "process-call",
  "zapier",
  "pipedream",
  "n8n",
  "edge",
  "test",
];

// ============================================================
// CHAIN CONFIGURATION
// ============================================================
const SEGMENT_LLM_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/segment-llm`;
const CONTEXT_ASSEMBLY_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/context-assembly`;
const AI_ROUTER_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-router`;

// ============================================================
// TYPES
// ============================================================
interface SegmentFromLLM {
  span_index: number;
  char_start: number;
  char_end: number;
  boundary_reason: string;
  confidence: number;
  boundary_quote: string | null;
}

interface SpanChainStatus {
  span_id: string;
  span_index: number;
  context_assembly_status: number | null;
  ai_router_status: number | null;
  error: string | null;
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
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
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const provenanceSource = body.source || "unknown";

  // Auth path 1: X-Edge-Secret + valid provenance source
  const hasValidEdgeSecret =
    expectedSecret &&
    edgeSecretHeader === expectedSecret &&
    ALLOWED_PROVENANCE_SOURCES.includes(provenanceSource);

  // Auth path 2: JWT + ALLOWED_EMAILS (with signature verification via auth.getUser)
  let hasValidJwt = false;
  let verifiedEmail = "";
  if (!hasValidEdgeSecret && authHeader?.startsWith("Bearer ")) {
    const anonClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const {
      data: { user },
      error: authErr,
    } = await anonClient.auth.getUser();

    if (!authErr && user?.email) {
      const allowedEmails = (Deno.env.get("ALLOWED_EMAILS") || "")
        .split(",")
        .map((e) => e.trim().toLowerCase());
      const userEmail = user.email.toLowerCase();
      hasValidJwt = allowedEmails.includes(userEmail);
      if (hasValidJwt) {
        verifiedEmail = userEmail;
        console.log(`[segment-call] JWT auth passed for: ${verifiedEmail}`);
      }
    }
  }

  if (!hasValidEdgeSecret && !hasValidJwt) {
    console.error(
      `[segment-call] Auth failed: source=${provenanceSource}, hasEdgeSecret=${!!edgeSecretHeader}, hasJwt=${!!authHeader}`
    );
    return new Response(
      JSON.stringify({
        ok: false,
        error: "unauthorized",
        error_code: "auth_failed",
        hint: "Requires X-Edge-Secret with valid source OR JWT with allowed email",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  console.log(
    `[segment-call] Auth passed: mode=${hasValidEdgeSecret ? "X-Edge-Secret" : "JWT"}, source=${provenanceSource}`
  );

  const {
    interaction_id,
    transcript,
    dry_run = false,
    max_segments = 10,
    min_segment_chars = 200,
  } = body;

  if (!interaction_id) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "missing_interaction_id",
        error_code: "bad_request",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!edgeSecret) {
    console.error("[segment-call] EDGE_SHARED_SECRET not configured");
    return new Response(
      JSON.stringify({
        ok: false,
        error: "config_error",
        error_code: "config_missing",
        hint: "EDGE_SHARED_SECRET not set",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  // ============================================================
  // 1. FETCH TRANSCRIPT (if not provided)
  // ============================================================
  let spanTranscript = transcript;
  if (!spanTranscript) {
    const { data: callsRaw, error: fetchErr } = await db
      .from("calls_raw")
      .select("transcript")
      .eq("interaction_id", interaction_id)
      .single();

    if (fetchErr || !callsRaw?.transcript) {
      console.error(
        `[segment-call] Failed to fetch transcript: ${fetchErr?.message || "not found"}`
      );
      return new Response(
        JSON.stringify({
          ok: false,
          error: "transcript_not_found",
          error_code: "no_transcript",
          interaction_id,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
    spanTranscript = callsRaw.transcript;
  }

  console.log(
    `[segment-call] Processing: interaction_id=${interaction_id}, transcript_len=${spanTranscript.length}`
  );

  // ============================================================
  // 2. RESEED CHECK: If span_attributions exist, return 409
  // ============================================================
  const { data: existingSpans } = await db
    .from("conversation_spans")
    .select("id")
    .eq("interaction_id", interaction_id);

  if (existingSpans && existingSpans.length > 0) {
    const spanIds = existingSpans.map((s) => s.id);
    const { data: existingAttribs, error: attribErr } = await db
      .from("span_attributions")
      .select("id")
      .in("span_id", spanIds)
      .limit(1);

    if (!attribErr && existingAttribs && existingAttribs.length > 0) {
      console.log(
        `[segment-call] Reseed blocked: interaction ${interaction_id} already has attributions`
      );
      return new Response(
        JSON.stringify({
          ok: false,
          error: "already_attributed",
          error_code: "already_attributed",
          interaction_id,
          hint: "Interaction already has span_attributions. Delete them first (requires CAMBER-1 approval).",
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 409, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // ============================================================
  // 3. CALL segment-llm FOR SEGMENTATION
  // ============================================================
  let segments: SegmentFromLLM[] = [];
  let segmenterVersion = "fallback_trivial_v1";
  let segmenterWarnings: string[] = [];

  try {
    console.log(`[segment-call] Calling segment-llm`);
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
      const errText = await llmResp.text();
      console.error(`[segment-call] segment-llm failed: ${llmResp.status} ${errText}`);
      // Fallback to single segment
      segments = [
        {
          span_index: 0,
          char_start: 0,
          char_end: spanTranscript.length,
          boundary_reason: "fallback_llm_failed",
          confidence: 1.0,
          boundary_quote: null,
        },
      ];
      segmenterWarnings.push(`segment_llm_failed_${llmResp.status}`);
    } else {
      const llmData = await llmResp.json();
      if (llmData.ok && Array.isArray(llmData.segments)) {
        segments = llmData.segments;
        segmenterVersion = llmData.segmenter_version || "segment-llm_v1.0.0";
        segmenterWarnings = llmData.warnings || [];
      } else {
        console.error(`[segment-call] segment-llm returned invalid data`);
        segments = [
          {
            span_index: 0,
            char_start: 0,
            char_end: spanTranscript.length,
            boundary_reason: "fallback_llm_invalid",
            confidence: 1.0,
            boundary_quote: null,
          },
        ];
        segmenterWarnings.push("segment_llm_invalid_response");
      }
    }
  } catch (llmErr: any) {
    console.error(`[segment-call] segment-llm fetch error: ${llmErr.message}`);
    segments = [
      {
        span_index: 0,
        char_start: 0,
        char_end: spanTranscript.length,
        boundary_reason: "fallback_llm_fetch_error",
        confidence: 1.0,
        boundary_quote: null,
      },
    ];
    segmenterWarnings.push("segment_llm_fetch_error");
  }

  console.log(`[segment-call] Got ${segments.length} segments from segmenter`);

  // ============================================================
  // 4. DELETE OLD SPANS (if any) and CREATE NEW SPANS
  // ============================================================
  // First delete any existing spans for this interaction (clean slate)
  if (existingSpans && existingSpans.length > 0) {
    const { error: deleteErr } = await db
      .from("conversation_spans")
      .delete()
      .eq("interaction_id", interaction_id);

    if (deleteErr) {
      console.error(`[segment-call] Failed to delete old spans: ${deleteErr.message}`);
      return new Response(
        JSON.stringify({
          ok: false,
          error: "span_delete_failed",
          error_code: "db_error",
          detail: deleteErr.message,
          version: SEGMENT_CALL_VERSION,
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  const now = new Date().toISOString();
  const spanRows = segments.map((seg) => {
    const segmentText = spanTranscript.slice(seg.char_start, seg.char_end);
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

  const { data: insertedSpans, error: spanErr } = await db
    .from("conversation_spans")
    .insert(spanRows)
    .select("id, span_index");

  if (spanErr) {
    console.error(`[segment-call] Span insert failed: ${spanErr.message}`);
    return new Response(
      JSON.stringify({
        ok: false,
        error: "span_creation_failed",
        error_code: "db_error",
        detail: spanErr.message,
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  const spanIds = insertedSpans.map((s) => s.id);
  const spanCount = insertedSpans.length;
  console.log(`[segment-call] Created ${spanCount} spans: ${spanIds.join(", ")}`);

  // ============================================================
  // 5. CHAIN: For each span → context-assembly → ai-router
  // ============================================================
  const chainStatuses: SpanChainStatus[] = [];

  for (const span of insertedSpans) {
    const status: SpanChainStatus = {
      span_id: span.id,
      span_index: span.span_index,
      context_assembly_status: null,
      ai_router_status: null,
      error: null,
    };

    try {
      // ========================================
      // 5a. CONTEXT-ASSEMBLY
      // ========================================
      console.log(
        `[segment-call] Chain span ${span.span_index}: context-assembly`
      );
      const contextResp = await fetch(CONTEXT_ASSEMBLY_URL, {
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

      status.context_assembly_status = contextResp.status;

      if (!contextResp.ok) {
        const errBody = await contextResp.text();
        console.error(
          `[segment-call] context-assembly failed for span ${span.span_index}: ${errBody}`
        );
        status.error = `context-assembly: ${contextResp.status}`;
        chainStatuses.push(status);
        continue;
      }

      const contextData = await contextResp.json();

      // ========================================
      // 5b. AI-ROUTER
      // ========================================
      if (contextData.context_package) {
        console.log(
          `[segment-call] Chain span ${span.span_index}: ai-router (dry_run=${dry_run})`
        );
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
          const errBody = await routerResp.text();
          console.error(
            `[segment-call] ai-router failed for span ${span.span_index}: ${errBody}`
          );
          status.error = `ai-router: ${routerResp.status}`;
        }
      } else {
        console.log(
          `[segment-call] No context_package for span ${span.span_index}, skipping ai-router`
        );
        status.error = "no_context_package";
      }
    } catch (chainErr: any) {
      console.error(
        `[segment-call] Chain error for span ${span.span_index}: ${chainErr.message}`
      );
      status.error = `chain_exception: ${chainErr.message}`;
    }

    chainStatuses.push(status);
  }

  // ============================================================
  // 6. RESPONSE
  // ============================================================
  const allSuccess = chainStatuses.every(
    (s) => s.context_assembly_status === 200 && s.ai_router_status === 200
  );

  return new Response(
    JSON.stringify({
      ok: true,
      version: SEGMENT_CALL_VERSION,
      interaction_id,
      span_ids: spanIds,
      span_count: spanCount,
      segmenter_version: segmenterVersion,
      segmenter_warnings: segmenterWarnings,
      chain: {
        attempted: true,
        auth_mode: "X-Edge-Secret",
        all_success: allSuccess,
        statuses: chainStatuses,
      },
      dry_run,
      ms: Date.now() - t0,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
