import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { evaluateAdjacentSpanCoherence, hasSwitchSignal } from "./adjacent_coherence_guardrails.ts";

Deno.test("switch signal detector catches explicit switch phrasing", () => {
  assertEquals(hasSwitchSignal("We are switching to the other project now"), true);
  assertEquals(hasSwitchSignal("Quick status update on permits"), false);
});

Deno.test("adjacent coherence overrides early-span project hop when no switch signal", () => {
  const result = evaluateAdjacentSpanCoherence({
    span_index: 2,
    transcript_text: "We are still at the same house finishing tile.",
    current_project_id: "proj-b",
    prior_assigned_project_ids: ["proj-a", "proj-a"],
    candidate_project_ids: ["proj-a", "proj-b"],
  });

  assertEquals(result.enforced, true);
  assertEquals(result.override_project_id, "proj-a");
  assertEquals(result.downgrade_to_review, false);
  assertEquals(result.reason, "adjacent_span_coherence_override");
});

Deno.test("adjacent coherence does not enforce when switch signal is present", () => {
  const result = evaluateAdjacentSpanCoherence({
    span_index: 3,
    transcript_text: "Let's switch over to the other project on Winship Road.",
    current_project_id: "proj-b",
    prior_assigned_project_ids: ["proj-a", "proj-a"],
    candidate_project_ids: ["proj-a", "proj-b"],
  });

  assertEquals(result.enforced, false);
  assertEquals(result.override_project_id, null);
  assertEquals(result.downgrade_to_review, false);
});

Deno.test("adjacent coherence skips when prior spans are mixed", () => {
  const result = evaluateAdjacentSpanCoherence({
    span_index: 2,
    transcript_text: "Still discussing work.",
    current_project_id: "proj-c",
    prior_assigned_project_ids: ["proj-a", "proj-b"],
    candidate_project_ids: ["proj-a", "proj-b", "proj-c"],
  });

  assertEquals(result.enforced, false);
  assertEquals(result.reason, null);
});
