/**
 * admin-reseed Edge Function
 * Re-chunk an interaction's conversation spans (non-destructive)
 *
 * @version 1.1.0
 * @date 2026-01-31
 * @purpose Supersede old spans and create new spans for an interaction
 *
 * TERMINOLOGY (STRAT directive 2026-01-31):
 * - Canonical term is "chunking" (not "segmentation")
 * - This endpoint performs "re-chunking" of conversation spans
 * - DB column names unchanged (segmenter_version, segment_reason, etc.)
 *
 * AUTH:
 * - Internal control-plane endpoint (not user-facing)
 * - Uses Pattern A: X-Edge-Secret + source allowlist
 * - verify_jwt=false
 *
 * BEHAVIOR:
 * 1. If any active span has human lock: return 409 human_lock_present
 * 2. Idempotency: if idempotency_key exists, return stored receipt (no mutation)
 * 3. Non-destructive: supersede old spans (is_superseded=true), insert new spans
 * 4. After rechunk, optionally reroute based on mode
 *
 * MODES (legacy names, concept is "rechunk"):
 * - resegment_only (default): Just rechunk, don't call downstream
 * - resegment_and_reroute: Rechunk + call context-assembly + ai-router
 *
 * FAIL CLOSED: Any DB write failure returns 500
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { requireEdgeSecret, authErrorResponse } from "../_shared/auth.ts";

const VERSION = "1.1.3";
const ALLOWED_SOURCES = ["admin-reseed", "system"];

interface ReseedRequest {
  interaction_id: string;
  reason: string;
  idempotency_key: string;
  mode?: "resegment_only" | "resegment_and_reroute";
  requested_by?: string;
}

interface ReseedReceipt {
  ok: boolean;
  interaction_id: string;
  idempotency_key: string;
  mode: string;
  span_count_before: number;
  span_count_after: number;
  attrib_count_before: number;
  attrib_count_after: number;
  status: "success" | "blocked_human_lock" | "error";
  human_locked_spans?: string[];
  new_span_ids?: string[];
  superseded_span_ids?: string[];
  reroute_triggered?: boolean;
  ms?: number;
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  // ========================================
  // 1. AUTH: X-Edge-Secret + source allowlist
  // ========================================
  const authResult = requireEdgeSecret(req, ALLOWED_SOURCES);
  if (!authResult.ok) {
    return authErrorResponse(authResult.error_code!);
  }

  // ========================================
  // 2. VALIDATE REQUEST
  // ========================================
  if (req.method !== "POST") {
    return jsonResponse({ error: "POST only" }, 405);
  }

  let body: ReseedRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const {
    interaction_id,
    reason,
    idempotency_key,
    mode = "resegment_only",
    requested_by = "system",
  } = body;

  // Validate required fields
  if (!interaction_id) {
    return jsonResponse({ error: "missing_interaction_id" }, 400);
  }
  if (!reason || reason.trim().length === 0) {
    return jsonResponse({ error: "missing_reason" }, 400);
  }
  if (!idempotency_key || idempotency_key.trim().length === 0) {
    return jsonResponse({ error: "missing_idempotency_key" }, 400);
  }
  if (!["resegment_only", "resegment_and_reroute"].includes(mode)) {
    return jsonResponse({ error: "invalid_mode", valid: ["resegment_only", "resegment_and_reroute"] }, 400);
  }

  // ========================================
  // 3. INIT DB CLIENT
  // ========================================
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ========================================
  // 4. IDEMPOTENCY CHECK
  // If idempotency_key exists, return stored receipt
  // ========================================
  const { data: existingLog } = await db
    .from("override_log")
    .select("effects_receipt, reseed_status")
    .eq("idempotency_key", idempotency_key)
    .maybeSingle();

  if (existingLog) {
    console.log(`[admin-reseed] Idempotent replay for key=${idempotency_key}`);
    const receipt = existingLog.effects_receipt as ReseedReceipt | null;
    return jsonResponse({
      ok: existingLog.reseed_status === "success",
      idempotent_replay: true,
      receipt: receipt || { status: existingLog.reseed_status },
      ms: Date.now() - t0,
    }, 200);
  }

  // ========================================
  // 5. VERIFY INTERACTION EXISTS
  // ========================================
  const { data: interaction, error: intErr } = await db
    .from("interactions")
    .select("interaction_id")
    .eq("interaction_id", interaction_id)
    .maybeSingle();

  if (intErr || !interaction) {
    return jsonResponse({
      ok: false,
      error: "interaction_not_found",
      interaction_id,
    }, 404);
  }

  // ========================================
  // 6. FETCH ACTIVE SPANS + CHECK HUMAN LOCKS
  // POLICY: Active spans only (is_superseded=false)
  // ========================================
  const { data: activeSpans, error: spanErr } = await db
    .from("conversation_spans")
    .select("id, span_index, segment_generation")
    .eq("interaction_id", interaction_id)
    .eq("is_superseded", false)
    .order("span_index");

  if (spanErr) {
    console.error("[admin-reseed] Failed to fetch spans:", spanErr.message);
    return jsonResponse({ ok: false, error: "db_read_failed", detail: spanErr.message }, 500);
  }

  const activeSpanIds = (activeSpans || []).map((s) => s.id);
  const spanCountBefore = activeSpanIds.length;
  const currentGeneration = Math.max(0, ...((activeSpans || []).map((s) => s.segment_generation || 1)));

  // Check for human locks on these spans
  let humanLockedSpans: string[] = [];
  let attribCountBefore = 0;

  if (activeSpanIds.length > 0) {
    const { data: attribs, error: attribErr } = await db
      .from("span_attributions")
      .select("span_id, attribution_lock")
      .in("span_id", activeSpanIds);

    if (attribErr) {
      console.error("[admin-reseed] Failed to fetch attributions:", attribErr.message);
      return jsonResponse({ ok: false, error: "db_read_failed", detail: attribErr.message }, 500);
    }

    attribCountBefore = (attribs || []).length;
    humanLockedSpans = (attribs || [])
      .filter((a) => a.attribution_lock === "human")
      .map((a) => a.span_id);
  }

  // ========================================
  // 7. HUMAN LOCK GATE
  // POLICY: If any human-locked span, return 409
  // ========================================
  if (humanLockedSpans.length > 0) {
    console.log(`[admin-reseed] Blocked: ${humanLockedSpans.length} human-locked spans`);

    const receipt: ReseedReceipt = {
      ok: false,
      interaction_id,
      idempotency_key,
      mode,
      span_count_before: spanCountBefore,
      span_count_after: spanCountBefore, // No change
      attrib_count_before: attribCountBefore,
      attrib_count_after: attribCountBefore, // No change
      status: "blocked_human_lock",
      human_locked_spans: humanLockedSpans,
    };

    // Write audit log even for blocked operations
    await writeOverrideLog(db, {
      interaction_id,
      idempotency_key,
      reason,
      mode,
      requested_by,
      receipt,
    });

    return jsonResponse({
      ok: false,
      error: "human_lock_present",
      human_locked_spans: humanLockedSpans,
      receipt,
      ms: Date.now() - t0,
    }, 409);
  }

  // ========================================
  // 8. SUPERSEDE OLD SPANS (non-destructive)
  // ========================================
  const reseedActionId = crypto.randomUUID();
  const newGeneration = currentGeneration + 1;

  if (activeSpanIds.length > 0) {
    const { error: supersedErr } = await db
      .from("conversation_spans")
      .update({
        is_superseded: true,
        superseded_at: new Date().toISOString(),
        superseded_by_action_id: reseedActionId,
      })
      .in("id", activeSpanIds);

    if (supersedErr) {
      console.error("[admin-reseed] Failed to supersede spans:", supersedErr.message);
      return jsonResponse({ ok: false, error: "db_write_failed", detail: supersedErr.message }, 500);
    }
  }

  // ========================================
  // 9. FETCH TRANSCRIPT FOR RECHUNKING
  // ========================================
  // Try transcripts_comparison first (canonical source)
  const { data: transcriptData } = await db
    .from("transcripts_comparison")
    .select("transcript, words")
    .eq("interaction_id", interaction_id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  let transcript = transcriptData?.transcript || "";

  // Fallback: reconstruct from existing spans if no transcript_comparison
  if (!transcript) {
    // Try active spans first, then fall back to most recent superseded generation
    let fallbackSpanIds = activeSpanIds;
    let fallbackSource = "active";

    if (fallbackSpanIds.length === 0) {
      // No active spans - get most recent superseded generation
      const { data: supersededSpans } = await db
        .from("conversation_spans")
        .select("id, segment_generation")
        .eq("interaction_id", interaction_id)
        .eq("is_superseded", true)
        .order("segment_generation", { ascending: false })
        .order("span_index");

      if (supersededSpans && supersededSpans.length > 0) {
        const maxGen = supersededSpans[0].segment_generation;
        fallbackSpanIds = supersededSpans
          .filter((s) => s.segment_generation === maxGen)
          .map((s) => s.id);
        fallbackSource = `superseded_gen${maxGen}`;
      }
    }

    if (fallbackSpanIds.length > 0) {
      const { data: spanTexts } = await db
        .from("conversation_spans")
        .select("transcript_segment, span_index")
        .in("id", fallbackSpanIds)
        .order("span_index");

      if (spanTexts && spanTexts.length > 0) {
        transcript = spanTexts
          .map((s) => s.transcript_segment || "")
          .filter(Boolean)
          .join("\n\n");
        console.log(`[admin-reseed] Reconstructed transcript from ${spanTexts.length} ${fallbackSource} spans, ${transcript.length} chars`);
      }
    }
  }

  // ========================================
  // 10. CREATE NEW SPANS (trivial chunker for now)
  // TODO: Replace with proper chunking logic (gap-based, topic-based, etc.)
  // ========================================
  const newSpanIds: string[] = [];

  if (transcript.length > 0) {
    // Trivial chunker: single span for entire transcript
    // Future: implement proper chunking based on gaps, topics, etc.
    const newSpanId = crypto.randomUUID();
    newSpanIds.push(newSpanId);

    const { error: insertErr } = await db
      .from("conversation_spans")
      .insert({
        id: newSpanId,
        interaction_id,
        span_index: 0,
        transcript_segment: transcript,
        word_count: transcript.split(/\s+/).filter(Boolean).length,
        segmenter_version: `reseed_trivial_v1`,
        segment_reason: `reseed:${reason}`,
        segment_generation: newGeneration,
        is_superseded: false,
      });

    if (insertErr) {
      console.error("[admin-reseed] Failed to insert new span:", insertErr.message);
      // FAIL CLOSED: rollback by marking old spans as not superseded
      if (activeSpanIds.length > 0) {
        await db
          .from("conversation_spans")
          .update({
            is_superseded: false,
            superseded_at: null,
            superseded_by_action_id: null,
          })
          .in("id", activeSpanIds);
      }
      return jsonResponse({ ok: false, error: "db_write_failed", detail: insertErr.message }, 500);
    }
  }

  // ========================================
  // 11. BUILD RECEIPT + WRITE AUDIT LOG
  // ========================================
  const receipt: ReseedReceipt = {
    ok: true,
    interaction_id,
    idempotency_key,
    mode,
    span_count_before: spanCountBefore,
    span_count_after: newSpanIds.length,
    attrib_count_before: attribCountBefore,
    attrib_count_after: 0, // New spans have no attributions yet
    status: "success",
    superseded_span_ids: activeSpanIds,
    new_span_ids: newSpanIds,
    reroute_triggered: false,
  };

  await writeOverrideLog(db, {
    interaction_id,
    idempotency_key,
    reason,
    mode,
    requested_by,
    receipt,
  });

  // ========================================
  // 12. OPTIONAL: TRIGGER REROUTE
  // ========================================
  if (mode === "resegment_and_reroute" && newSpanIds.length > 0) {
    receipt.reroute_triggered = true;

    // Call context-assembly -> ai-router for each new span
    const contextAssemblyUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/context-assembly`;
    const aiRouterUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-router`;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const edgeSecret = Deno.env.get("EDGE_SHARED_SECRET");

    // Headers for internal function-to-function calls
    const internalHeaders: Record<string, string> = {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${serviceKey}`,
    };
    // Add X-Edge-Secret if available for additional auth path
    if (edgeSecret) {
      internalHeaders["X-Edge-Secret"] = edgeSecret;
      internalHeaders["X-Source"] = "admin-reseed";
    }

    for (const spanId of newSpanIds) {
      try {
        // Call context-assembly
        const ctxResp = await fetch(contextAssemblyUrl, {
          method: "POST",
          headers: internalHeaders,
          body: JSON.stringify({ span_id: spanId }),
        });

        if (!ctxResp.ok) {
          const errText = await ctxResp.text().catch(() => "");
          console.error(`[admin-reseed] context-assembly failed for span ${spanId}: ${ctxResp.status} ${errText}`);
          continue;
        }

        const ctxData = await ctxResp.json();
        if (!ctxData.ok || !ctxData.context_package) {
          console.error(`[admin-reseed] context-assembly returned no package for span ${spanId}`);
          continue;
        }

        // Call ai-router
        const routerResp = await fetch(aiRouterUrl, {
          method: "POST",
          headers: internalHeaders,
          body: JSON.stringify({
            context_package: ctxData.context_package,
            dry_run: false,
          }),
        });

        if (!routerResp.ok) {
          console.error(`[admin-reseed] ai-router failed for span ${spanId}: ${routerResp.status}`);
        } else {
          console.log(`[admin-reseed] Rerouted span ${spanId}`);
        }
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : "Unknown error";
        console.error(`[admin-reseed] Reroute error for span ${spanId}: ${msg}`);
      }
    }
  }

  // ========================================
  // 13. RESPONSE
  // ========================================
  console.log(
    `[admin-reseed] Rechunk completed: interaction=${interaction_id}, spans_before=${spanCountBefore}, spans_after=${newSpanIds.length}, ` +
      `mode=${mode}, reroute=${receipt.reroute_triggered}`,
  );

  return jsonResponse({
    ok: true,
    receipt: { ...receipt, ms: Date.now() - t0 },
  }, 200);
});

// ============================================================
// HELPERS
// ============================================================

function jsonResponse(data: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function writeOverrideLog(
  db: ReturnType<typeof createClient>,
  params: {
    interaction_id: string;
    idempotency_key: string;
    reason: string;
    mode: string;
    requested_by: string;
    receipt: ReseedReceipt;
  },
): Promise<void> {
  const { error } = await db
    .from("override_log")
    .insert({
      entity_type: "reseed",
      entity_key: `interaction:${params.interaction_id}`,
      field_name: "conversation_spans",
      from_value: `generation:${params.receipt.span_count_before}`,
      to_value: `generation:${params.receipt.span_count_after}`,
      reason: params.reason,
      idempotency_key: params.idempotency_key,
      mode: params.mode,
      requested_by: params.requested_by,
      interaction_id: params.interaction_id,
      span_count_before: params.receipt.span_count_before,
      span_count_after: params.receipt.span_count_after,
      attrib_count_before: params.receipt.attrib_count_before,
      attrib_count_after: params.receipt.attrib_count_after,
      reseed_status: params.receipt.status,
      effects_receipt: params.receipt,
    });

  if (error) {
    console.error("[admin-reseed] Failed to write override_log:", error.message);
    // Don't fail the whole operation for audit log failure
    // But log it clearly
  }
}
