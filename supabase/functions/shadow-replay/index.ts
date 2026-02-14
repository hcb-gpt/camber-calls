/**
 * shadow-replay Edge Function v0.1.0
 *
 * Auth (internal gate; verify_jwt=false):
 * - X-Edge-Secret == EDGE_SHARED_SECRET
 *
 * Input:
 * - interaction_id (required): original production call interaction id
 * - shadow_id (optional): explicit shadow interaction id (must start with cll_SHADOW_)
 * - dry_run (optional): if true, do not call process-call
 *
 * Output:
 * - { ok, shadow_id, pipeline_result }
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const VERSION = "v0.1.0";
const jsonHeaders = { "Content-Type": "application/json" };
const SHADOW_ID_PATTERN = /^cll_SHADOW_[a-zA-Z0-9_]+$/;

function makeShadowId(): string {
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 8).toUpperCase();
  return `cll_SHADOW_${ts}_${rand}`;
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: false, error: "POST only", version: VERSION }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const edgeSecretHeader = req.headers.get("X-Edge-Secret");
  const expectedSecret = Deno.env.get("EDGE_SHARED_SECRET");
  const hasValidEdgeSecret = expectedSecret && edgeSecretHeader === expectedSecret;
  if (!hasValidEdgeSecret) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "unauthorized",
        error_code: "auth_failed",
        hint: "Requires X-Edge-Secret matching EDGE_SHARED_SECRET",
        version: VERSION,
      }),
      { status: 401, headers: jsonHeaders },
    );
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ ok: false, error: "invalid_json", version: VERSION }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const interactionId = String(body?.interaction_id || "").trim();
  if (!interactionId) {
    return new Response(
      JSON.stringify({ ok: false, error: "missing_interaction_id", version: VERSION }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const dryRun = body?.dry_run === true;
  const explicitShadowId = String(body?.shadow_id || "").trim();
  const shadowId = explicitShadowId || makeShadowId();

  if (!SHADOW_ID_PATTERN.test(shadowId)) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "invalid_shadow_id",
        hint: "shadow_id must start with cll_SHADOW_ and contain only [a-zA-Z0-9_]",
        version: VERSION,
      }),
      { status: 400, headers: jsonHeaders },
    );
  }

  if (shadowId === interactionId) {
    return new Response(
      JSON.stringify({ ok: false, error: "shadow_id_must_differ", version: VERSION }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ ok: false, error: "config_missing", version: VERSION }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const db = createClient(supabaseUrl, serviceRoleKey);
  const { data: original, error: originalErr } = await db
    .from("calls_raw")
    .select(
      "interaction_id,transcript,event_at_utc,direction,owner_phone,other_party_phone,recording_url,owner_name,other_party_name,summary",
    )
    .eq("interaction_id", interactionId)
    .maybeSingle();

  if (originalErr || !original) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "original_call_not_found",
        detail: originalErr?.message || null,
        interaction_id: interactionId,
        version: VERSION,
      }),
      { status: 404, headers: jsonHeaders },
    );
  }

  if (!original.transcript || String(original.transcript).trim().length < 10) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "original_transcript_missing",
        interaction_id: interactionId,
        version: VERSION,
      }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const shadowPayload = {
    interaction_id: shadowId,
    call_id: shadowId,
    event_at_utc: original.event_at_utc,
    call_start_utc: original.event_at_utc,
    direction: original.direction,
    transcript: original.transcript,
    summary: original.summary,
    from_phone: original.owner_phone,
    to_phone: original.other_party_phone,
    owner_phone: original.owner_phone,
    other_party_phone: original.other_party_phone,
    owner_name: original.owner_name,
    other_party_name: original.other_party_name,
    recording_url: original.recording_url,
    source: "shadow",
    is_shadow: true,
    _shadow_replay_meta: {
      source_interaction_id: interactionId,
      replayed_at_utc: new Date().toISOString(),
      version: VERSION,
    },
  };

  if (dryRun) {
    return new Response(
      JSON.stringify({
        ok: true,
        version: VERSION,
        interaction_id: interactionId,
        shadow_id: shadowId,
        dry_run: true,
        pipeline_result: null,
        payload_preview: {
          source: "shadow",
          is_shadow: true,
          transcript_chars: String(original.transcript).length,
          has_event_at_utc: Boolean(original.event_at_utc),
        },
        ms: Date.now() - t0,
      }),
      { status: 200, headers: jsonHeaders },
    );
  }

  const processCallUrl = `${supabaseUrl}/functions/v1/process-call`;
  let processResp: Response;
  try {
    processResp = await fetch(processCallUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceRoleKey}`,
        apikey: serviceRoleKey,
        "X-Edge-Secret": expectedSecret,
      },
      body: JSON.stringify(shadowPayload),
    });
  } catch (e: any) {
    return new Response(
      JSON.stringify({
        ok: false,
        error: "process_call_fetch_failed",
        detail: e?.message || "unknown_error",
        interaction_id: interactionId,
        shadow_id: shadowId,
        version: VERSION,
      }),
      { status: 502, headers: jsonHeaders },
    );
  }

  const processText = await processResp.text();
  let pipelineResult: unknown = processText;
  try {
    pipelineResult = JSON.parse(processText);
  } catch {
    // Keep text body if not JSON.
  }

  return new Response(
    JSON.stringify({
      ok: processResp.ok,
      version: VERSION,
      interaction_id: interactionId,
      shadow_id: shadowId,
      dry_run: false,
      pipeline_status: processResp.status,
      pipeline_result: pipelineResult,
      ms: Date.now() - t0,
    }),
    { status: processResp.ok ? 200 : 502, headers: jsonHeaders },
  );
});
