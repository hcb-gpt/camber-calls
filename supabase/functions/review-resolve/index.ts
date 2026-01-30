/**
 * review-resolve Edge Function
 * Human resolution endpoint for pending review items
 *
 * @version 1.0.0
 * @date 2026-01-30
 * @purpose Close the product loop: human resolves pending item → SSOT + audit updated
 *
 * EXPANDED SCOPE (CHAD decision):
 * - span_attributions: applied_project_id, attribution_lock='human', needs_review=false
 * - review_queue: status='resolved'
 * - override_log: audit row
 * - scheduler_items: project_id + attribution_status (via interaction)
 * - journal_claims: project_id (via call_id/interaction)
 *
 * Hard rules:
 * - Never downgrade human lock
 * - Idempotency: duplicate resolve = no-op (return success)
 * - Failures must return non-200 + log span_id
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ResolveRequest {
  review_queue_id: string;
  chosen_project_id: string;
  notes?: string;
}

interface ResolveResponse {
  ok: boolean;
  review_queue_id: string;
  span_id: string | null;
  interaction_id: string | null;
  chosen_project_id: string;
  was_already_resolved: boolean;
  updates: {
    span_attributions: boolean;
    review_queue: boolean;
    override_log: boolean;
    scheduler_items: number;
    journal_claims: number;
  };
  ms: number;
  error?: string;
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
  // 2. INIT DB CLIENT
  // ========================================
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ========================================
  // 3. LOAD REVIEW QUEUE ITEM
  // ========================================
  const { data: reviewItem, error: loadError } = await db
    .from("review_queue")
    .select("*")
    .eq("id", review_queue_id)
    .maybeSingle();

  if (loadError) {
    console.error("[review-resolve] Failed to load review_queue:", loadError.message);
    return jsonResponse({ error: "db_error_loading_review_item", detail: loadError.message }, 500);
  }

  if (!reviewItem) {
    return jsonResponse({ error: "review_queue_item_not_found" }, 404);
  }

  const span_id = reviewItem.span_id;
  const interaction_id = reviewItem.interaction_id;

  // ========================================
  // 4. IDEMPOTENCY CHECK: already resolved?
  // ========================================
  if (reviewItem.status === "resolved" || reviewItem.status === "dismissed") {
    // No-op: item already resolved. Return success.
    console.log(`[review-resolve] Item ${review_queue_id} already ${reviewItem.status}, no-op`);
    return jsonResponse({
      ok: true,
      review_queue_id,
      span_id,
      interaction_id,
      chosen_project_id,
      was_already_resolved: true,
      updates: {
        span_attributions: false,
        review_queue: false,
        override_log: false,
        scheduler_items: 0,
        journal_claims: 0,
      },
      ms: Date.now() - t0,
    }, 200);
  }

  // Require pending status
  if (reviewItem.status !== "pending") {
    return jsonResponse({ error: "review_queue_item_not_pending", current_status: reviewItem.status }, 400);
  }

  // ========================================
  // 5. LOCK CHECK: never downgrade human lock
  // ========================================
  if (span_id) {
    const { data: existingAttr } = await db
      .from("span_attributions")
      .select("attribution_lock")
      .eq("span_id", span_id)
      .maybeSingle();

    if (existingAttr?.attribution_lock === "human") {
      // Already has human lock - this should be rare but is not an error
      // Just update review_queue to resolved
      console.log(`[review-resolve] Span ${span_id} already has human lock, updating review_queue only`);
    }
  }

  // ========================================
  // 6. BUILD IDEMPOTENCY KEY FOR AUDIT
  // ========================================
  const _idempotency_key = `resolve:${review_queue_id}:${chosen_project_id}`;

  // Check if audit row already exists (idempotency)
  const { data: existingAudit } = await db
    .from("override_log")
    .select("id")
    .eq("review_queue_id", review_queue_id)
    .eq("to_value", chosen_project_id)
    .maybeSingle();

  const updates = {
    span_attributions: false,
    review_queue: false,
    override_log: false,
    scheduler_items: 0,
    journal_claims: 0,
  };

  // ========================================
  // 7. WRITE AUDIT ROW (if not duplicate)
  // ========================================
  if (!existingAudit) {
    // Get current project_id from span_attributions for from_value
    let fromValue: string | null = null;
    if (span_id) {
      const { data: currentAttr } = await db
        .from("span_attributions")
        .select("applied_project_id")
        .eq("span_id", span_id)
        .maybeSingle();
      fromValue = currentAttr?.applied_project_id || null;
    }

    const { error: auditError } = await db.from("override_log").insert({
      entity_type: "span_attribution",
      entity_id: span_id,
      field_name: "applied_project_id",
      from_value: fromValue,
      to_value: chosen_project_id,
      user_id: "human_reviewer", // TODO: extract from JWT when auth is wired
      reason: notes || "Resolved via review-resolve endpoint",
      review_queue_id,
    });

    if (auditError) {
      console.error("[review-resolve] override_log insert failed:", auditError.message);
      // Non-blocking: continue with other updates
    } else {
      updates.override_log = true;
    }
  }

  // ========================================
  // 8. UPDATE SPAN_ATTRIBUTIONS (SSOT)
  // ========================================
  if (span_id) {
    const { error: attrError } = await db
      .from("span_attributions")
      .update({
        applied_project_id: chosen_project_id,
        attribution_lock: "human",
        needs_review: false,
        applied_at_utc: new Date().toISOString(),
      })
      .eq("span_id", span_id);

    if (attrError) {
      console.error("[review-resolve] span_attributions update failed:", attrError.message);
      return jsonResponse({ error: "ssot_update_failed", detail: attrError.message, span_id }, 500);
    }
    updates.span_attributions = true;
  }

  // ========================================
  // 9. RESOLVE REVIEW_QUEUE
  // ========================================
  const { error: resolveError } = await db
    .from("review_queue")
    .update({
      status: "resolved",
      resolved_at: new Date().toISOString(),
      resolved_by: "human_reviewer", // TODO: extract from JWT
      resolution_action: "confirmed",
      resolution_notes: notes || null,
    })
    .eq("id", review_queue_id)
    .eq("status", "pending"); // Ensure we only update if still pending

  if (resolveError) {
    console.error("[review-resolve] review_queue resolve failed:", resolveError.message);
    // Non-fatal: SSOT was already updated
  } else {
    updates.review_queue = true;
  }

  // ========================================
  // 10. EXPANDED: UPDATE SCHEDULER_ITEMS
  // ========================================
  if (interaction_id) {
    const { data: schedulerResult, error: schedulerError } = await db
      .from("scheduler_items")
      .update({
        project_id: chosen_project_id,
        attribution_status: "resolved",
        needs_review: false,
      })
      .eq("interaction_id", interaction_id)
      .select("id");

    if (schedulerError) {
      console.error("[review-resolve] scheduler_items update failed:", schedulerError.message);
    } else {
      updates.scheduler_items = schedulerResult?.length || 0;
    }
  }

  // ========================================
  // 11. EXPANDED: UPDATE JOURNAL_CLAIMS
  // ========================================
  // journal_claims uses call_id, which we need to get from interactions
  if (interaction_id) {
    const { data: interactionData } = await db
      .from("interactions")
      .select("interaction_id")
      .eq("id", interaction_id)
      .maybeSingle();

    const call_id = interactionData?.interaction_id; // The external call_id

    if (call_id) {
      const { data: claimsResult, error: claimsError } = await db
        .from("journal_claims")
        .update({
          project_id: chosen_project_id,
        })
        .eq("call_id", call_id)
        .select("id");

      if (claimsError) {
        console.error("[review-resolve] journal_claims update failed:", claimsError.message);
      } else {
        updates.journal_claims = claimsResult?.length || 0;
      }
    }
  }

  // ========================================
  // 12. RESPONSE
  // ========================================
  console.log(
    `[review-resolve] Resolved ${review_queue_id}: span=${span_id}, project=${chosen_project_id}, ` +
      `updates: attr=${updates.span_attributions}, queue=${updates.review_queue}, ` +
      `audit=${updates.override_log}, sched=${updates.scheduler_items}, claims=${updates.journal_claims}`,
  );

  return jsonResponse({
    ok: true,
    review_queue_id,
    span_id,
    interaction_id,
    chosen_project_id,
    was_already_resolved: false,
    updates,
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
