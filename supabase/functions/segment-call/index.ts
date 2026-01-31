/**
 * segment-call Edge Function v1.2.0
 * Span producer: segments calls into conversation spans, then chains to context-assembly → ai-router
 *
 * @version 1.2.0
 * @date 2026-01-31
 * @purpose Create conversation_spans from calls_raw, then trigger attribution chain
 *
 * PR-12/STRAT TURN25:
 * - Use X-Edge-Secret for downstream calls (not Bearer SERVICE_ROLE_KEY)
 * - Add chain logging: chain_attempted, chain_auth_mode, router_status
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SEGMENT_CALL_VERSION = "v1.2.0";

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

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

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
    span_id = `span_${interaction_id}_${Date.now()}`;

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

    // Create span
    const { error: spanErr } = await db.from("conversation_spans").upsert({
      id: span_id,
      interaction_id,
      transcript_text: span_transcript,
      speaker_label: "UNKNOWN",
      start_ms: 0,
      end_ms: (span_transcript?.length || 0) * 50, // Rough estimate
      created_at: now,
    }, { onConflict: "id" });

    if (spanErr) {
      console.error("[segment-call] Span creation failed:", spanErr.message);
      return new Response(
        JSON.stringify({ error: "span_creation_failed", detail: spanErr.message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }

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
