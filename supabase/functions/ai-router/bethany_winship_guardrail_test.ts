import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { applyBethanyRoadWinshipGuardrail } from "./bethany_winship_guardrail.ts";

Deno.test("bethany winship guardrail: forces misattributed bethany address to winship", () => {
  const out = applyBethanyRoadWinshipGuardrail({
    decision: "assign",
    project_id: "hurley",
    confidence: 0.8,
    reasoning: "Model picked Hurley from mixed evidence.",
    anchors: [
      {
        candidate_project_id: "hurley",
        match_type: "address_fragment",
        text: "Lake Bethany Road",
        quote: "getting close to the Lake Bethany Road",
      },
    ],
    candidates: [
      {
        project_id: "winship",
        project_name: "Winship Residence",
        address: "123 Bethany Road, Madison, GA",
        evidence: {
          alias_matches: [{ term: "Bethany Road", match_type: "address_fragment" }],
        },
      },
      {
        project_id: "hurley",
        project_name: "Hurley Residence",
        address: "999 Other Rd",
        evidence: { alias_matches: [] },
      },
    ],
  });

  assertEquals(out.applied, true);
  assertEquals(out.decision, "assign");
  assertEquals(out.project_id, "winship");
  assertEquals(out.confidence, 0.8);
  assertStringIncludes(out.reasoning, "Deterministic Bethany Road gate forced Winship assignment.");
});

Deno.test("bethany winship guardrail: does not override when strong conflicting client anchor exists", () => {
  const out = applyBethanyRoadWinshipGuardrail({
    decision: "assign",
    project_id: "hurley",
    confidence: 0.84,
    reasoning: "Model picked Hurley from client name and address evidence.",
    anchors: [
      {
        candidate_project_id: "hurley",
        match_type: "address_fragment",
        text: "Bethany Road",
        quote: "Bethany Road is where the job is",
      },
      {
        candidate_project_id: "hurley",
        match_type: "client_name",
        text: "Hurley",
        quote: "Mr Hurley wants custom doors",
      },
    ],
    candidates: [
      {
        project_id: "winship",
        project_name: "Winship Residence",
        address: "Bethany Road",
        evidence: {
          alias_matches: [{ term: "Bethany Road", match_type: "address_fragment" }],
        },
      },
      {
        project_id: "hurley",
        project_name: "Hurley Residence",
        address: "Bethany Road",
        evidence: {
          alias_matches: [{ term: "Bethany Road", match_type: "address_fragment" }],
        },
      },
    ],
  });

  assertEquals(out.applied, false);
  assertEquals(out.project_id, "hurley");
  assertEquals(out.reason, "conflicting_strong_anchor");
});

Deno.test("bethany winship guardrail: no-op without bethany address anchor", () => {
  const out = applyBethanyRoadWinshipGuardrail({
    decision: "review",
    project_id: null,
    confidence: 0.63,
    reasoning: "No clear anchor.",
    anchors: [
      {
        candidate_project_id: "winship",
        match_type: "city_or_location",
        text: "Madison",
        quote: "over in Madison",
      },
    ],
    candidates: [
      {
        project_id: "winship",
        project_name: "Winship Residence",
        address: "Bethany Road",
        evidence: {
          alias_matches: [{ term: "Bethany Road", match_type: "address_fragment" }],
        },
      },
    ],
  });

  assertEquals(out.applied, false);
  assertEquals(out.decision, "review");
  assertEquals(out.project_id, null);
  assertEquals(out.reason, "no_bethany_address_anchor");
});
