import {
  applyWorldModelReferenceGuardrail,
  buildWorldModelFactsCandidateSummary,
  filterProjectFactsForPrompt,
  parseWorldModelReferences,
} from "./world_model_facts.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected=${String(expected)} actual=${String(actual)}`);
  }
}

Deno.test("project facts filter: same-call exclusion is respected", () => {
  const filtered = filterProjectFactsForPrompt(
    [{
      project_id: "proj-1",
      facts: [
        {
          project_id: "proj-1",
          as_of_at: "2026-02-01T00:00:00Z",
          observed_at: "2026-02-02T00:00:00Z",
          fact_kind: "address",
          fact_payload: { street: "123 Main St" },
          evidence_event_id: "evt_same",
          interaction_id: "cll_same",
        },
        {
          project_id: "proj-1",
          as_of_at: "2026-01-20T00:00:00Z",
          observed_at: "2026-01-20T00:00:00Z",
          fact_kind: "material_spec",
          fact_payload: { countertop: "mystery white quartz" },
          evidence_event_id: "evt_keep",
          interaction_id: "cll_old",
        },
      ],
    }],
    {
      interaction_id: "cll_same",
      current_evidence_event_ids: ["evt_same"],
      max_per_project: 20,
    },
  );

  assertEquals(filtered.length, 1, "expected one project pack");
  assertEquals(filtered[0].facts.length, 1, "same-call fact should be removed");
  assertEquals(filtered[0].facts[0].fact_kind, "material_spec", "remaining fact should be older fact");
});

Deno.test("world model summary: empty facts do not break formatting", () => {
  const summary = buildWorldModelFactsCandidateSummary("proj-1", [], 3);
  assertEquals(summary, "   - World model facts: none", "empty facts should render safe fallback");
});

Deno.test("world model summary: prompt formatting is stable", () => {
  const summary = buildWorldModelFactsCandidateSummary(
    "proj-1",
    [{
      project_id: "proj-1",
      facts: [
        {
          project_id: "proj-1",
          as_of_at: "2026-01-02T10:00:00Z",
          observed_at: "2026-01-03T11:00:00Z",
          fact_kind: "address",
          fact_payload: { street: "123 Main St", city: "Athens" },
          evidence_event_id: "evt_1",
          interaction_id: "cll_old_1",
        },
        {
          project_id: "proj-1",
          as_of_at: "2026-01-05T10:00:00Z",
          observed_at: "2026-01-06T11:00:00Z",
          fact_kind: "material_spec",
          fact_payload: { countertop: "mystery white quartz" },
          evidence_event_id: "evt_2",
          interaction_id: "cll_old_2",
        },
      ],
    }],
    2,
  );

  const expected = "   - World model facts (2; corroboration only):\n" +
    "     1. [address] as_of=2026-01-02 observed=2026-01-03 fact=street=123 Main St; city=Athens\n" +
    "     2. [material_spec] as_of=2026-01-05 observed=2026-01-06 fact=countertop=mystery white quartz";
  assertEquals(summary, expected, "world model prompt block should remain stable");
});

Deno.test("world model guardrail: weak-only fact references downgrade assign", () => {
  const refs = parseWorldModelReferences([
    {
      project_id: "proj-1",
      fact_kind: "status_note",
      fact_as_of_at: "2026-01-01T00:00:00Z",
      fact_excerpt: "status is active and discussed in prior call",
      relevance: "related status context",
    },
  ]);
  const result = applyWorldModelReferenceGuardrail({
    decision: "assign",
    project_id: "proj-1",
    transcript: "we discussed the update but not the final details yet",
    world_model_references: refs,
    project_facts: [{
      project_id: "proj-1",
      facts: [
        {
          project_id: "proj-1",
          as_of_at: "2026-01-01T00:00:00Z",
          observed_at: "2026-01-01T00:00:00Z",
          fact_kind: "status_note",
          fact_payload: { note: "active update in progress" },
          evidence_event_id: null,
          interaction_id: "cll_old",
        },
      ],
    }],
  });

  assertEquals(result.decision, "review", "assign should be downgraded for weak-only fact references");
  assertEquals(result.reason_code, "world_model_fact_weak_only", "reason code should explain downgrade");
  assert(result.world_model_references.length === 1, "validated reference should remain for audit");
});
