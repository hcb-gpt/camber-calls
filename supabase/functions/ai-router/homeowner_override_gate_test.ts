import { assertEquals } from "jsr:@std/assert";
import { evaluateHomeownerOverride, homeownerOverrideActsAsStrongAnchor } from "./homeowner_override_gate.ts";

Deno.test("homeowner override: active with no conflict metadata", () => {
  assertEquals(
    homeownerOverrideActsAsStrongAnchor({
      homeowner_override: true,
      homeowner_override_project_id: "proj_123",
      homeowner_override_conflict_project_id: null,
      homeowner_override_conflict_term: null,
    }),
    true,
  );
});

Deno.test("homeowner override: inactive when override flag is false", () => {
  assertEquals(
    homeownerOverrideActsAsStrongAnchor({
      homeowner_override: false,
      homeowner_override_project_id: "proj_123",
    }),
    false,
  );
});

Deno.test("homeowner override: inactive when conflict project exists", () => {
  assertEquals(
    homeownerOverrideActsAsStrongAnchor({
      homeowner_override: true,
      homeowner_override_project_id: "proj_123",
      homeowner_override_conflict_project_id: "proj_conflict",
      homeowner_override_conflict_term: null,
    }),
    false,
  );
});

Deno.test("homeowner override: inactive when conflict term exists", () => {
  assertEquals(
    homeownerOverrideActsAsStrongAnchor({
      homeowner_override: true,
      homeowner_override_project_id: "proj_123",
      homeowner_override_conflict_project_id: null,
      homeowner_override_conflict_term: "permar",
    }),
    false,
  );
});

Deno.test("homeowner override evaluation: active and deterministic when single candidate", () => {
  const out = evaluateHomeownerOverride(
    {
      homeowner_override: true,
      homeowner_override_project_id: "proj_homeowner",
      homeowner_override_conflict_project_id: null,
      homeowner_override_conflict_term: null,
    },
    ["proj_homeowner"],
  );

  assertEquals(out.strong_anchor_active, true);
  assertEquals(out.deterministic_project_id, "proj_homeowner");
  assertEquals(out.skip_reason, null);
});

Deno.test("homeowner override evaluation: blocks deterministic gate on multi-project span", () => {
  const out = evaluateHomeownerOverride(
    {
      homeowner_override: true,
      homeowner_override_project_id: "proj_homeowner",
      homeowner_override_conflict_project_id: null,
      homeowner_override_conflict_term: null,
    },
    ["proj_homeowner", "proj_other"],
  );

  assertEquals(out.strong_anchor_active, false);
  assertEquals(out.deterministic_project_id, null);
  assertEquals(out.skip_reason, "multi_project_span");
});

Deno.test("homeowner override evaluation: requires homeowner project id", () => {
  const out = evaluateHomeownerOverride(
    {
      homeowner_override: true,
      homeowner_override_project_id: " ",
      homeowner_override_conflict_project_id: null,
      homeowner_override_conflict_term: null,
    },
    [],
  );

  assertEquals(out.strong_anchor_active, false);
  assertEquals(out.deterministic_project_id, null);
  assertEquals(out.skip_reason, "missing_project_id");
});
