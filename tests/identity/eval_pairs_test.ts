/**
 * eval_pairs_test.ts — Minimal CI fixture validation
 *
 * Validates:
 * 1. eval_pairs.json is valid JSON with expected schema
 * 2. All test cases have required fields
 * 3. Nickname whitelist is non-empty and well-formed
 * 4. No duplicate test case IDs
 * 5. Spot-check: known decisions match expectations
 */
import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const fixture = JSON.parse(
  Deno.readTextFileSync(new URL("./eval_pairs.json", import.meta.url)),
);

Deno.test("fixture has valid top-level schema", () => {
  assertExists(fixture.version, "missing version");
  assertExists(fixture.config, "missing config");
  assertExists(fixture.nickname_whitelist, "missing nickname_whitelist");
  assertExists(fixture.test_cases, "missing test_cases");
  assertExists(fixture.test_cases.name_pairs, "missing name_pairs");
  assertExists(
    fixture.test_cases.anchor_integration,
    "missing anchor_integration",
  );
  assertExists(
    fixture.test_cases.camber_edge_cases,
    "missing camber_edge_cases",
  );
});

Deno.test("config has required threshold fields", () => {
  const cfg = fixture.config;
  assertExists(cfg.phonetic_algorithm);
  assertExists(cfg.similarity_metric);
  assertExists(cfg.thresholds);
  assertEquals(typeof cfg.thresholds.standard, "number");
  assertEquals(typeof cfg.thresholds.short_code_4char, "number");
  assertEquals(typeof cfg.thresholds.reject_below_chars, "number");
  assertEquals(typeof cfg.short_token_min_length, "number");
  assertEquals(typeof cfg.weak_confidence_cap, "number");
});

Deno.test("nickname whitelist is non-empty and well-formed", () => {
  const wl = fixture.nickname_whitelist;
  const entries = Object.entries(wl);
  assertEquals(
    entries.length > 20,
    true,
    `expected 20+ entries, got ${entries.length}`,
  );

  for (const [short, full] of entries) {
    assertEquals(typeof short, "string", `key must be string: ${short}`);
    assertEquals(
      typeof full,
      "string",
      `value must be string for key: ${short}`,
    );
    assertEquals(short.length > 0, true, "empty key");
    assertEquals(
      (full as string).length > 0,
      true,
      `empty value for key: ${short}`,
    );
    assertEquals(short, short.toLowerCase(), `key must be lowercase: ${short}`);
  }
});

Deno.test("all name_pairs have required fields", () => {
  for (const tc of fixture.test_cases.name_pairs) {
    assertExists(tc.id, "missing id");
    assertEquals(typeof tc.name_a, "string", `${tc.id}: name_a must be string`);
    assertEquals(typeof tc.name_b, "string", `${tc.id}: name_b must be string`);
    assertExists(tc.expected_decision, `${tc.id}: missing expected_decision`);
    assertExists(tc.reason, `${tc.id}: missing reason`);
  }
});

Deno.test("all anchor_integration cases have required fields", () => {
  for (const tc of fixture.test_cases.anchor_integration) {
    assertExists(tc.id, "missing id");
    assertEquals(typeof tc.name_a, "string", `${tc.id}: name_a must be string`);
    assertEquals(typeof tc.name_b, "string", `${tc.id}: name_b must be string`);
    assertExists(tc.expected_decision, `${tc.id}: missing expected_decision`);
    assertExists(tc.reason, `${tc.id}: missing reason`);
  }
});

Deno.test("all camber_edge_cases have required fields", () => {
  for (const tc of fixture.test_cases.camber_edge_cases) {
    assertExists(tc.id, "missing id");
    assertEquals(typeof tc.name_a, "string", `${tc.id}: name_a must be string`);
    assertEquals(typeof tc.name_b, "string", `${tc.id}: name_b must be string`);
    assertExists(tc.expected_decision, `${tc.id}: missing expected_decision`);
    assertExists(tc.reason, `${tc.id}: missing reason`);
  }
});

Deno.test("no duplicate test case IDs", () => {
  const allCases = [
    ...fixture.test_cases.name_pairs,
    ...fixture.test_cases.anchor_integration,
    ...fixture.test_cases.camber_edge_cases,
  ];
  const ids = allCases.map((tc: { id: string }) => tc.id);
  const uniqueIds = new Set(ids);
  assertEquals(
    ids.length,
    uniqueIds.size,
    `duplicate IDs found: ${
      ids.filter((id: string, i: number) => ids.indexOf(id) !== i)
    }`,
  );
});

Deno.test("minimum test case counts", () => {
  assertEquals(
    fixture.test_cases.name_pairs.length >= 25,
    true,
    `expected 25+ name pairs, got ${fixture.test_cases.name_pairs.length}`,
  );
  assertEquals(
    fixture.test_cases.anchor_integration.length >= 10,
    true,
    `expected 10+ anchor tests, got ${fixture.test_cases.anchor_integration.length}`,
  );
  assertEquals(
    fixture.test_cases.camber_edge_cases.length >= 3,
    true,
    `expected 3+ edge cases, got ${fixture.test_cases.camber_edge_cases.length}`,
  );
});

// Spot checks — verify known decisions
Deno.test("spot check: Bob/Robert = MATCH", () => {
  const np01 = fixture.test_cases.name_pairs.find((tc: { id: string }) =>
    tc.id === "NP-01"
  );
  assertExists(np01, "NP-01 missing");
  assertEquals(np01.expected_decision, "MATCH");
});

Deno.test("spot check: Brian Dove/Brian Young = REJECT", () => {
  const np03 = fixture.test_cases.name_pairs.find((tc: { id: string }) =>
    tc.id === "NP-03"
  );
  assertExists(np03, "NP-03 missing");
  assertEquals(np03.expected_decision, "REJECT");
});

Deno.test("spot check: Unknown Caller = REJECT", () => {
  const ce01 = fixture.test_cases.camber_edge_cases.find((tc: { id: string }) =>
    tc.id === "CE-01"
  );
  assertExists(ce01, "CE-01 missing");
  assertEquals(ce01.expected_decision, "REJECT");
});

Deno.test("spot check: phone anchor = AUTO_MERGE", () => {
  const ai01 = fixture.test_cases.anchor_integration.find((
    tc: { id: string },
  ) => tc.id === "AI-01");
  assertExists(ai01, "AI-01 missing");
  assertEquals(ai01.expected_decision, "AUTO_MERGE");
});

Deno.test("whitelist includes new additions (Debbie, Randy, Mitch)", () => {
  assertEquals(fixture.nickname_whitelist["debbie"], "deborah");
  assertEquals(fixture.nickname_whitelist["randy"], "randall");
  assertEquals(fixture.nickname_whitelist["mitch"], "mitchell");
});
