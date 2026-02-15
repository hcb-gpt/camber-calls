import { applyCommonAliasCorroborationGuardrail, isCommonWordAlias } from "./alias_guardrails.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected=${String(expected)} actual=${String(actual)}`);
  }
}

Deno.test("common alias classifier: flags material/color aliases, preserves project-specific aliases", () => {
  assert(isCommonWordAlias("mystery white"), "expected 'mystery white' to be treated as common");
  assert(isCommonWordAlias("white"), "expected 'white' to be treated as common");
  assert(isCommonWordAlias("granite"), "expected 'granite' to be treated as common");
  assert(!isCommonWordAlias("Skelton Residence"), "expected residence-style alias to remain project-specific");
  assert(!isCommonWordAlias("Sittler Residence"), "expected surname+residence alias to remain project-specific");
});

Deno.test("common alias guardrail: downgrades assign when only common alias evidence exists", () => {
  const out = applyCommonAliasCorroborationGuardrail({
    decision: "assign",
    project_id: "proj-1",
    anchors: [
      {
        candidate_project_id: "proj-1",
        match_type: "alias",
        text: "white",
        quote: "we picked mystery white for the kitchen marble",
      },
    ],
  });

  assertEquals(out.decision, "review", "assign should be downgraded");
  assertEquals(out.downgraded, true, "downgrade flag should be set");
  assertEquals(out.common_alias_unconfirmed, true, "common_alias_unconfirmed should be true");
  assert(
    out.flagged_alias_terms.includes("white"),
    "flagged aliases should include the ambiguous alias",
  );
});

Deno.test("common alias guardrail: allows assign when corroborating evidence exists", () => {
  const out = applyCommonAliasCorroborationGuardrail({
    decision: "assign",
    project_id: "proj-1",
    anchors: [
      {
        candidate_project_id: "proj-1",
        match_type: "alias",
        text: "white",
        quote: "we picked mystery white for the kitchen marble",
      },
      {
        candidate_project_id: "proj-1",
        match_type: "address_fragment",
        text: "Skelton Road",
        quote: "at the Skelton Road house we need this installed",
      },
    ],
  });

  assertEquals(out.decision, "assign", "assign should remain when corroborated");
  assertEquals(out.downgraded, false, "downgrade flag should remain false");
  assertEquals(out.common_alias_unconfirmed, false, "common_alias_unconfirmed should remain false");
});
