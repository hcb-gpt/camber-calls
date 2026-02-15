import { assert, assertEquals, assertExists } from "https://deno.land/std@0.218.0/assert/mod.ts";

type JsonRecord = Record<string, unknown>;

type CanonicalCallRow = {
  interaction_id: string;
  transcript: string | null;
  event_at_utc: string | null;
  direction: string | null;
  owner_phone: string | null;
  other_party_phone: string | null;
};

const CANONICAL_INTERACTION_ID = "cll_06DSX0CVZHZK72VCVW54EH9G3C";
const RUN_PIPELINE_INTEGRATION = Deno.env.get("RUN_PIPELINE_INTEGRATION") === "1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";
const EDGE_SHARED_SECRET = Deno.env.get("EDGE_SHARED_SECRET") ?? "";

const FUNCTION_BASE_URL = `${SUPABASE_URL}/functions/v1`;

function hasRequiredConfig(): boolean {
  return Boolean(
    SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY && EDGE_SHARED_SECRET,
  );
}

function makeIntegrationId(label: string): string {
  const suffix = crypto.randomUUID().replace(/-/g, "").slice(0, 10);
  return `cll_ITEST_${label}_${suffix}`;
}

async function decodeJson(response: Response): Promise<JsonRecord> {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text) as JsonRecord;
  } catch {
    return { raw: text };
  }
}

function buildEdgeHeaders(source: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    "apikey": SUPABASE_SERVICE_ROLE_KEY,
    "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    "X-Edge-Secret": EDGE_SHARED_SECRET,
    "X-Source": source,
  };
}

async function invokeEdgeFunction(
  functionName: string,
  payload: JsonRecord,
  source: string,
): Promise<{ status: number; body: JsonRecord }> {
  const response = await fetch(`${FUNCTION_BASE_URL}/${functionName}`, {
    method: "POST",
    headers: buildEdgeHeaders(source),
    body: JSON.stringify({ ...payload, source }),
  });

  return {
    status: response.status,
    body: await decodeJson(response),
  };
}

async function fetchCanonicalCall(): Promise<CanonicalCallRow> {
  const query = `interaction_id=eq.${
    encodeURIComponent(CANONICAL_INTERACTION_ID)
  }&select=interaction_id,transcript,event_at_utc,direction,owner_phone,other_party_phone&limit=1`;
  const response = await fetch(`${SUPABASE_URL}/rest/v1/calls_raw?${query}`, {
    method: "GET",
    headers: {
      "apikey": SUPABASE_SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    },
  });

  assertEquals(response.status, 200, "failed to fetch canonical call fixture");
  const rows = (await response.json()) as CanonicalCallRow[];
  assert(rows.length > 0, "canonical call fixture not found in calls_raw");
  assert(
    rows[0].transcript && rows[0].transcript.length >= 10,
    "canonical call transcript missing/too short",
  );
  return rows[0];
}

function integrationEnabled(): boolean {
  return RUN_PIPELINE_INTEGRATION && hasRequiredConfig();
}

Deno.test({
  name: "integration scaffold: process-call -> segment-call -> segment-llm -> context-assembly -> ai-router",
  ignore: !integrationEnabled(),
  fn: async () => {
    const canonical = await fetchCanonicalCall();
    const interactionId = makeIntegrationId("CHAIN");
    const transcript = canonical.transcript as string;
    const eventAt = canonical.event_at_utc ?? new Date().toISOString();

    const processResult = await invokeEdgeFunction("process-call", {
      interaction_id: interactionId,
      call_id: interactionId,
      transcript,
      event_at_utc: eventAt,
      direction: canonical.direction ?? "inbound",
      owner_phone: canonical.owner_phone,
      other_party_phone: canonical.other_party_phone,
    }, "test");

    assertEquals(processResult.status, 200);
    assertEquals(processResult.body.ok, true);
    assertEquals(processResult.body.interaction_id, interactionId);
    assertExists(processResult.body.decision);
    assertExists(processResult.body.segment_call);

    const segmentResult = await invokeEdgeFunction("segment-call", {
      interaction_id: interactionId,
      transcript,
      dry_run: true,
      max_segments: 8,
      min_segment_chars: 120,
    }, "test");

    assertEquals(segmentResult.status, 200);
    assertEquals(segmentResult.body.ok, true);
    assert(
      Array.isArray(segmentResult.body.span_ids),
      "segment-call span_ids must be an array",
    );
    assert(
      (segmentResult.body.span_ids as unknown[]).length > 0,
      "segment-call should return at least one span",
    );
    assertExists(segmentResult.body.segmenter_version);

    const segmentLlmResult = await invokeEdgeFunction("segment-llm", {
      interaction_id: interactionId,
      transcript,
      max_segments: 8,
      min_segment_chars: 120,
    }, "segment-call");

    assertEquals(segmentLlmResult.status, 200);
    assertEquals(segmentLlmResult.body.ok, true);
    assert(
      Array.isArray(segmentLlmResult.body.segments),
      "segment-llm segments must be an array",
    );
    assert(
      (segmentLlmResult.body.segments as unknown[]).length > 0,
      "segment-llm should return at least one segment",
    );
    assertExists(segmentLlmResult.body.segmenter_version);

    const spanIds = segmentResult.body.span_ids as string[];
    const firstSpanId = spanIds[0];

    const contextResult = await invokeEdgeFunction("context-assembly", {
      span_id: firstSpanId,
    }, "segment-call");

    assertEquals(contextResult.status, 200);
    assertEquals(contextResult.body.ok, true);
    assertExists(contextResult.body.context_package);
    const contextPackage = contextResult.body.context_package as JsonRecord;
    const contextMeta = contextPackage.meta as JsonRecord;
    assertEquals(contextMeta.span_id, firstSpanId);
    assertEquals(contextMeta.interaction_id, interactionId);

    const routerResult = await invokeEdgeFunction("ai-router", {
      context_package: contextPackage,
      dry_run: true,
    }, "segment-call");

    assertEquals(routerResult.status, 200);
    assertEquals(routerResult.body.ok, true);
    assertEquals(routerResult.body.span_id, firstSpanId);
    assertExists(routerResult.body.decision);
    assertExists(routerResult.body.confidence);
  },
});

Deno.test({
  name: "integration scaffold negative: missing transcript is flagged",
  ignore: !integrationEnabled(),
  fn: async () => {
    const interactionId = makeIntegrationId("NEG_EMPTY_TRANSCRIPT");
    const processResult = await invokeEdgeFunction("process-call", {
      interaction_id: interactionId,
      call_id: interactionId,
      transcript: "",
      event_at_utc: new Date().toISOString(),
      direction: "inbound",
      owner_phone: null,
      other_party_phone: null,
    }, "test");

    assertEquals(processResult.status, 200);
    assertEquals(processResult.body.ok, true);
    assertEquals(processResult.body.decision, "NEEDS_REVIEW");
    const reasons = processResult.body.reasons as string[];
    assert(Array.isArray(reasons), "reasons should be an array");
    assert(
      reasons.includes("G4_EMPTY_TRANSCRIPT"),
      "expected G4_EMPTY_TRANSCRIPT reason",
    );

    const interactionQuery = `interaction_id=eq.${
      encodeURIComponent(interactionId)
    }&select=interaction_id,needs_review,review_reasons&limit=1`;
    const interactionResp = await fetch(
      `${SUPABASE_URL}/rest/v1/interactions?${interactionQuery}`,
      {
        method: "GET",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      },
    );
    assertEquals(interactionResp.status, 200, "failed to fetch interaction row");
    const interactionRows = (await interactionResp.json()) as Array<{
      interaction_id: string;
      needs_review: boolean | null;
      review_reasons: string[] | null;
    }>;
    assert(interactionRows.length > 0, "interaction row missing");
    assertEquals(interactionRows[0].needs_review, false);
    assert(
      Array.isArray(interactionRows[0].review_reasons) &&
        interactionRows[0].review_reasons.includes("terminal_empty_transcript") &&
        interactionRows[0].review_reasons.includes("G4_EMPTY_TRANSCRIPT"),
      "expected terminal_empty_transcript review reason",
    );

    const reviewQueueQuery = `interaction_id=eq.${
      encodeURIComponent(interactionId)
    }&status=eq.pending&select=id,span_id,status&limit=20`;
    const reviewQueueResp = await fetch(
      `${SUPABASE_URL}/rest/v1/review_queue?${reviewQueueQuery}`,
      {
        method: "GET",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      },
    );
    assertEquals(reviewQueueResp.status, 200, "failed to fetch review_queue rows");
    const reviewQueueRows = (await reviewQueueResp.json()) as Array<{
      id: string;
      span_id: string | null;
      status: string;
    }>;
    assertEquals(reviewQueueRows.length, 0, "expected no pending review_queue rows for empty transcript");
  },
});

Deno.test({
  name: "integration scaffold negative: null phone does not fail request",
  ignore: !integrationEnabled(),
  fn: async () => {
    const canonical = await fetchCanonicalCall();
    const interactionId = makeIntegrationId("NEG_NULL_PHONE");
    const processResult = await invokeEdgeFunction("process-call", {
      interaction_id: interactionId,
      call_id: interactionId,
      transcript: canonical.transcript as string,
      event_at_utc: canonical.event_at_utc ?? new Date().toISOString(),
      direction: canonical.direction ?? "inbound",
      owner_phone: null,
      other_party_phone: null,
    }, "test");

    assertEquals(processResult.status, 200);
    assertEquals(processResult.body.ok, true);
    assertEquals(processResult.body.interaction_id, interactionId);
  },
});

Deno.test({
  name: "integration scaffold negative: malformed interaction_id is flagged",
  ignore: !integrationEnabled(),
  fn: async () => {
    const canonical = await fetchCanonicalCall();
    const malformedId = `bad-${crypto.randomUUID().slice(0, 8)}`;
    const processResult = await invokeEdgeFunction("process-call", {
      interaction_id: malformedId,
      call_id: malformedId,
      transcript: canonical.transcript as string,
      event_at_utc: canonical.event_at_utc ?? new Date().toISOString(),
      direction: canonical.direction ?? "inbound",
      owner_phone: canonical.owner_phone,
      other_party_phone: canonical.other_party_phone,
    }, "test");

    assertEquals(processResult.status, 200);
    assertEquals(processResult.body.ok, true);
    assertEquals(processResult.body.decision, "NEEDS_REVIEW");
    const reasons = processResult.body.reasons as string[];
    assert(Array.isArray(reasons), "reasons should be an array");
    assert(
      reasons.includes("G1_ID_MALFORMED"),
      "expected G1_ID_MALFORMED reason",
    );
  },
});
