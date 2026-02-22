/**
 * auto-review-resolver Edge Function v1.0.0
 * Runs the auto-review resolver RPC (dry-run or apply mode).
 *
 * Behavior:
 * - Auto-resolve review_queue items with confidence >= high threshold
 * - Auto-dismiss review_queue items with confidence < low threshold
 * - Leave middle band for human review
 *
 * Auth:
 * - X-Edge-Secret + source allowlist
 * - OR service role key in Authorization Bearer token
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { authErrorResponse, requireEdgeSecret } from "../_shared/auth.ts";

const VERSION = "auto-review-resolver_v1.0.0";
const DEFAULT_HIGH_CONF = 0.85;
const DEFAULT_LOW_CONF = 0.20;
const DEFAULT_LIMIT = 500;
const ALLOWED_SOURCES = [
  "agent-teams",
  "auto-review-resolver",
  "cron",
  "claude-chat",
  "test",
];

interface AutoReviewResolverRequest {
  dry_run?: boolean;
  limit?: number;
  high_confidence_threshold?: number;
  low_confidence_threshold?: number;
  actor?: string;
}

interface ExtendedAuthResult {
  ok: boolean;
  error_code?: string;
  detail?: string;
  method?: string;
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "POST_ONLY" }, 405);
  }

  const auth = authenticateRequest(req);
  if (!auth.ok) {
    return authErrorResponse(auth.error_code || "missing_edge_secret", auth.detail);
  }

  let body: AutoReviewResolverRequest = {};
  try {
    const text = await req.text();
    if (text.trim().length > 0) {
      body = JSON.parse(text);
    }
  } catch {
    return jsonResponse({ ok: false, error: "INVALID_JSON" }, 400);
  }

  const dryRun = body.dry_run === true;
  const limit = Number.isInteger(body.limit) ? Number(body.limit) : DEFAULT_LIMIT;
  const high = typeof body.high_confidence_threshold === "number"
    ? body.high_confidence_threshold
    : DEFAULT_HIGH_CONF;
  const low = typeof body.low_confidence_threshold === "number"
    ? body.low_confidence_threshold
    : DEFAULT_LOW_CONF;
  const actor = (body.actor && body.actor.trim()) || "system:auto_review_resolver_edge";

  if (!Number.isFinite(high) || !Number.isFinite(low) || low < 0 || high > 1 || low >= high) {
    return jsonResponse({
      ok: false,
      error: "INVALID_THRESHOLDS",
      detail: "Require 0 <= low_confidence_threshold < high_confidence_threshold <= 1",
    }, 400);
  }
  if (!Number.isInteger(limit) || limit < 1 || limit > 5000) {
    return jsonResponse({
      ok: false,
      error: "INVALID_LIMIT",
      detail: "limit must be an integer between 1 and 5000",
    }, 400);
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await db.rpc("run_auto_review_resolver", {
    p_high_conf: high,
    p_low_conf: low,
    p_limit: limit,
    p_actor: actor,
    p_dry_run: dryRun,
  });

  if (error) {
    return jsonResponse({
      ok: false,
      error: "RPC_FAILED",
      detail: error.message,
      params: { dry_run: dryRun, high, low, limit, actor },
    }, 500);
  }

  const result = typeof data === "string" ? JSON.parse(data) : data;
  return jsonResponse({
    ok: true,
    version: VERSION,
    auth_method: auth.method,
    params: { dry_run: dryRun, high, low, limit, actor },
    result,
    ms: Date.now() - t0,
  }, 200);
});

function authenticateRequest(req: Request): ExtendedAuthResult {
  const edgeSecret = req.headers.get("X-Edge-Secret");
  if (edgeSecret) {
    const result = requireEdgeSecret(req, ALLOWED_SOURCES);
    if (result.ok) {
      return { ok: true, method: "edge_secret", detail: result.source };
    }
    return {
      ok: false,
      error_code: result.error_code,
      detail: `edge_secret: ${result.error_code}`,
    };
  }

  const authHeader = req.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.replace("Bearer ", "");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (serviceRoleKey && token === serviceRoleKey) {
      return { ok: true, method: "service_role" };
    }
    return {
      ok: false,
      error_code: "invalid_auth_token",
      detail: "Only service_role key or X-Edge-Secret accepted",
    };
  }

  return {
    ok: false,
    error_code: "missing_edge_secret",
    detail: "Provide X-Edge-Secret header or Authorization: Bearer <service_role_key>",
  };
}

function jsonResponse(data: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-edge-secret, x-source, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
