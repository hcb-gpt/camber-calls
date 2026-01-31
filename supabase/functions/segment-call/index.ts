/**
 * segment-call Edge Function v1.3.0
 * Span producer: segments calls into conversation spans, then chains to context-assembly → ai-router
 *
 * @version 1.3.0
 * @date 2026-01-31
 * @purpose Create conversation_spans from calls_raw, then trigger attribution chain
 *
 * PR-12/STRAT TURN25:
 * - Use X-Edge-Secret for downstream calls (not Bearer SERVICE_ROLE_KEY)
 * - Add chain logging: chain_attempted, chain_auth_mode, router_status
 *
 * v1.3.0:
 * - Added internal auth gate: X-Edge-Secret OR JWT+ALLOWED_EMAILS
 * - Requires verify_jwt: false in config.toml (auth handled internally)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGMENT_CALL_VERSION = "v1.4.0";

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
const CONTEXT_ASSEMBLY_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/context-assembly`;
const AI_ROUTER_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-router`;

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
  const hasValidEdgeSecret = expectedSecret &&
    edgeSecretHeader === expectedSecret &&
    ALLOWED_PROVENANCE_SOURCES.includes(provenanceSource);

  // Auth path 2: JWT + ALLOWED_EMAILS (with signature verification via auth.getUser)
  let hasValidJwt = false;
  let verifiedEmail = "";
  if (!hasValidEdgeSecret && authHeader?.startsWith("Bearer ")) {
    // Use Supabase auth.getUser() to verify JWT signature (not just decode)
    const anonClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: authErr } = await anonClient.auth.getUser();

    if (!authErr && user?.email) {
      const allowedEmails = (Deno.env.get("ALLOWED_EMAILS") || "").split(",").map((e) => e.trim().toLowerCase());
      const userEmail = user.email.toLowerCase();
      hasValidJwt = allowedEmails.includes(userEmail);
      if (hasValidJwt) {
        verifiedEmail = userEmail;
        console.log(`[segment-call] JWT auth passed for: ${verifiedEmail}`);
      }
    }
  }

  if (!hasValidEdgeSecret && !hasValidJwt) {
    console.error(`[segment-call] Auth failed: source=${provenanceSource}, hasEdgeSecret=${!!edgeSecretHeader}, hasJwt=${!!authHeader}`);
    return new Response(
      JSON.stringify({
        error: "unauthorized",
        hint: "Requires X-Edge-Secret with valid source OR JWT with allowed email",
        version: SEGMENT_CALL_VERSION,
      }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  console.log(`[segment-call] Auth passed: mode=${hasValidEdgeSecret ? "X-Edge-Secret" : "JWT"}, source=${provenanceSource}`);

  const { interaction_id, transcript, dry_run = false } = body;

  if (!interaction_id) {
    return new Response(JSON.stringify({ error: "missing_interaction_id" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get EDGE_SHARED_SECRET for downstream auth
  const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");
  if (!edgeSecret) {
    console.error("[segment-call] EDGE_SHARED_SECRET not configured");
    return new Response(
      JSON.stringify({ error: "config_error", hint: "EDGE_SHARED_SECRET not set" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  let span_id: string | null = null;
  let context_assembly_status: number | null = null;
  let ai_router_status: number | null = null;
  let chain_error: string | null = null;

  try {
    // ========================================
    // 1. CREATE SPAN
    // ========================================
    const now = new Date().toISOString();

    // Get transcript from calls_raw if not provided
    let span_transcript = transcript;
    if (!span_transcript) {
      const { data: callsRaw } = await db
        .from("calls_raw")
        .select("transcript")
        .eq("interaction_id", interaction_id)
        .single();

      span_transcript = callsRaw?.transcript || "";
    }

    // Create span (matching conversation_spans schema)
    const wordCount = span_transcript ? span_transcript.split(/\s+/).filter(Boolean).length : 0;
    const { data: spanData, error: spanErr } = await db.from("conversation_spans").upsert({
      interaction_id,
      span_index: 0,  // trivial segmenter: 1 span per call
      char_start: 0,
      char_end: span_transcript?.length || 0,
      transcript_segment: span_transcript,
      word_count: wordCount,
      segmenter_version: "segment-call_v1.3.1",
      segment_reason: "full_call",
      created_at: now,
    }, { onConflict: "interaction_id,span_index" }).select("id").single();

    if (spanErr) {
      console.error("[segment-call] Span creation failed:", spanErr.message);
      return new Response(
        JSON.stringify({ error: "span_creation_failed", detail: spanErr.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

    span_id = spanData?.id || `${interaction_id}:0`;
    console.log(`[segment-call] Span created: ${span_id}`);

    // ========================================
    // 2. CHAIN TO CONTEXT-ASSEMBLY
    // ========================================
    console.log(`[segment-call] Chain: context-assembly (auth_mode=X-Edge-Secret, dry_run=${dry_run})`);

    try {
      const contextResp = await fetch(CONTEXT_ASSEMBLY_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Edge-Secret": edgeSecret,
        },
        body: JSON.stringify({
          span_id,
          interaction_id,
          source: "segment-call",
        }),
      });

      context_assembly_status = contextResp.status;
      console.log(`[segment-call] context-assembly response: ${context_assembly_status}`);

      if (!contextResp.ok) {
        const errBody = await contextResp.text();
        console.error(`[segment-call] context-assembly failed: ${errBody}`);
        chain_error = `context-assembly: ${context_assembly_status}`;
      } else {
        const contextData = await contextResp.json();

        // ========================================
        // 3. CHAIN TO AI-ROUTER (if context-assembly succeeded)
        // ========================================
        if (contextData.context_package) {
          console.log(`[segment-call] Chain: ai-router (auth_mode=X-Edge-Secret, dry_run=${dry_run})`);

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

            ai_router_status = routerResp.status;
            console.log(`[segment-call] ai-router response: ${ai_router_status}`);

            if (!routerResp.ok) {
              const errBody = await routerResp.text();
              console.error(`[segment-call] ai-router failed: ${errBody}`);
              chain_error = `ai-router: ${ai_router_status}`;
            }
          } catch (routerErr: any) {
            console.error(`[segment-call] ai-router fetch error: ${routerErr.message}`);
            chain_error = `ai-router_fetch: ${routerErr.message}`;
          }
        } else {
          console.log("[segment-call] No context_package from context-assembly, skipping ai-router");
        }
      }
    } catch (contextErr: any) {
      console.error(`[segment-call] context-assembly fetch error: ${contextErr.message}`);
      chain_error = `context-assembly_fetch: ${contextErr.message}`;
    }

    return new Response(
      JSON.stringify({
        ok: true,
        version: SEGMENT_CALL_VERSION,
        span_id,
        interaction_id,
        chain: {
          attempted: true,
          auth_mode: "X-Edge-Secret",
          context_assembly_status,
          ai_router_status,
          error: chain_error,
        },
        dry_run,
        ms: Date.now() - t0,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e: any) {
    console.error(`[segment-call] Error: ${e.message}`);
    return new Response(
      JSON.stringify({
        ok: false,
        version: SEGMENT_CALL_VERSION,
        span_id,
        interaction_id,
        error: e.message,
        ms: Date.now() - t0,
      }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
