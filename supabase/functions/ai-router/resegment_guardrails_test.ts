import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { evaluateAutoResegmentInvariant } from "./resegment_guardrails.ts";

Deno.test("auto-resegment invariant triggers on oversized span", () => {
  const result = evaluateAutoResegmentInvariant({
    span_chars: 3201,
    anchors: [],
  });

  assertEquals(result.triggered, true);
  assertEquals(result.reasons.includes("span_chars_over_3000"), true);
  assertEquals(result.strong_anchor_project_count, 0);
});

Deno.test("auto-resegment invariant triggers on multiple strong anchor projects", () => {
  const result = evaluateAutoResegmentInvariant({
    span_chars: 400,
    anchors: [
      { match_type: "exact_project_name", candidate_project_id: "proj-a" },
      { match_type: "alias", candidate_project_id: "proj-b" },
      { match_type: "city_or_location", candidate_project_id: "proj-c" },
    ],
  });

  assertEquals(result.triggered, true);
  assertEquals(result.reasons.includes("multiple_strong_anchor_projects"), true);
  assertEquals(result.strong_anchor_project_count, 2);
});

Deno.test("auto-resegment invariant stays off for normal span and single strong project", () => {
  const result = evaluateAutoResegmentInvariant({
    span_chars: 900,
    anchors: [
      { match_type: "alias", candidate_project_id: "proj-a" },
      { match_type: "city_or_location", candidate_project_id: "proj-b" },
    ],
  });

  assertEquals(result.triggered, false);
  assertEquals(result.reasons.length, 0);
  assertEquals(result.strong_anchor_project_count, 1);
});

Deno.test("auto-resegment invariant includes additional strong project IDs from context", () => {
  const result = evaluateAutoResegmentInvariant({
    span_chars: 1200,
    anchors: [],
    additional_strong_project_ids: ["proj-a", "proj-b"],
  });

  assertEquals(result.triggered, true);
  assertEquals(result.reasons.includes("multiple_strong_anchor_projects"), true);
  assertEquals(result.strong_anchor_project_count, 2);
});
