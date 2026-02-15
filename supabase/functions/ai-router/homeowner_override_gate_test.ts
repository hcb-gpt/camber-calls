import { assertEquals } from "jsr:@std/assert";
import { homeownerOverrideActsAsStrongAnchor } from "./homeowner_override_gate.ts";

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
