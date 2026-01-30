/**
 * review-resolve Edge Function
 * Human resolution endpoint for pending review items
 *
 * @version 3.0.0
 * @date 2026-01-30
 * @purpose Close the product loop: human resolves pending item → SSOT + audit updated
 *
 * IMPLEMENTATION: Calls resolve_review_item() RPC for single-transaction atomicity
 *
 * EXPANDED SCOPE (CHAD decision):
 * - span_attributions: applied_project_id, attribution_lock='human', needs_review=false
 * - review_queue: status='resolved'
 * - override_log: audit row with idempotency_key
 * - scheduler_items: project_id + attribution_status (via interaction, NULL only)
 * - journal_claims: project_id (via call_id/interaction, NULL only)
 *
 * Hard rules:
 * - Never downgrade human lock
 * - Cannot overwrite human-locked span with different project
 * - Idempotency: duplicate resolve = no-op (return success)
 * - Failures must return non-200 + raise exception (txn rollback)
 * - All writes in single transaction (RPC handles this)
 * - Actor extracted from JWT (no hardcoded values)
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ResolveRequest {
  review_queue_id: string;
  chosen_project_id: string;
  notes?: string;
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  // ========================================
  // 1. VALIDATE REQUEST
  // ========================================
  if (req.method !== "POST") {
    return jsonResponse({ error: "POST only" }, 405);
  }

  let body: ResolveRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }

  const { review_queue_id, chosen_project_id, notes } = body;

  if (!review_queue_id || !isValidUUID(review_queue_id)) {
    return jsonResponse({ error: "missing_or_invalid_review_queue_id" }, 400);
  }
  if (!chosen_project_id || !isValidUUID(chosen_project_id)) {
    return jsonResponse({ error: "missing_or_invalid_chosen_project_id" }, 400);
  }

  // ========================================
  // 2. EXTRACT ACTOR FROM JWT
  // ========================================
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "missing_authorization_header" }, 401);
  }

  const token = authHeader.replace("Bearer ", "");
  let user_id: string;

  try {
    // Decode JWT payload (base64url)
    const payloadB64 = token.split(".")[1];
    if (!payloadB64) {
      throw new Error("Invalid JWT format");
    }
    const payload = JSON.parse(atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")));

    // Extract user identifier: prefer sub, fallback to email
    user_id = payload.sub || payload.email || null;

    if (!user_id) {
      return jsonResponse({
        error: "jwt_missing_user_id",
        detail: "JWT must contain sub or email claim",
      }, 401);
    }
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return jsonResponse({
      error: "jwt_decode_failed",
      detail: message,
    }, 401);
  }

  // ========================================
  // 3. INIT DB CLIENT
  // ========================================
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ========================================
  // 4. CALL RPC (single transaction)
  // ========================================
  const { data, error } = await db.rpc("resolve_review_item", {
    p_review_queue_id: review_queue_id,
    p_chosen_project_id: chosen_project_id,
    p_notes: notes || null,
    p_user_id: user_id,
  });

  if (error) {
    console.error("[review-resolve] RPC failed:", error.message);

    // Check if it's an SSOT assertion failure (raised exception)
    if (error.message.includes("SSOT_UPDATE_FAILED")) {
      return jsonResponse({
        ok: false,
        error: "ssot_update_failed",
        detail: error.message,
        review_queue_id,
      }, 500);
    }

    return jsonResponse({
      ok: false,
      error: "rpc_failed",
      detail: error.message,
      review_queue_id,
    }, 500);
  }

  // RPC returns jsonb, parse if needed
  const result = typeof data === "string" ? JSON.parse(data) : data;

  if (!result.ok) {
    // RPC returned an error (not found, not pending, human_lock_conflict, etc.)
    let status = 400;
    if (result.error === "review_queue_item_not_found") status = 404;
    if (result.error === "missing_user_id") status = 401;
    if (result.error === "human_lock_conflict") status = 409;

    return jsonResponse({ ...result, ms: Date.now() - t0 }, status);
  }

  // ========================================
  // 5. LOG + RESPONSE
  // ========================================
  console.log(
    `[review-resolve] Resolved ${review_queue_id}: span=${result.span_id}, project=${chosen_project_id}, ` +
      `actor=${user_id}, was_already_resolved=${result.was_already_resolved}, updates=${
        JSON.stringify(result.updates)
      }`,
  );

  return jsonResponse({
    ...result,
    ms: Date.now() - t0,
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

function isValidUUID(str: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str);
}
