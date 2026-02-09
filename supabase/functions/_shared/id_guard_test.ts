import { assert, assertEquals } from "https://deno.land/std@0.218.0/assert/mod.ts";
import { hasIdGuardErrors, summarizeIdGuardWarnings, validateAttributionIds } from "./id_guard.ts";

Deno.test("id_guard: accepts canonical interaction_id and span_id", () => {
  const issues = validateAttributionIds({
    interaction_id: "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W",
    span_id: "d1f8a85c-c047-422c-9951-09f4564aba3d",
  });

  assertEquals(issues.length, 0);
  assertEquals(hasIdGuardErrors(issues), false);
  assertEquals(summarizeIdGuardWarnings(issues), []);
});

Deno.test("id_guard: flags OCR-confusable interaction prefix without auto-correction", () => {
  const issues = validateAttributionIds({
    interaction_id: "c11_06E0P6KYB5V7S5VYQA8ZTRQM4W",
  });

  assert(issues.some((i) => i.code === "interaction_id_confusable_prefix"));
  assert(issues.some((i) => i.code === "interaction_id_invalid_format"));
  assertEquals(hasIdGuardErrors(issues), true);
  const confusable = issues.find((i) => i.code === "interaction_id_confusable_prefix");
  assertEquals(confusable?.as_received, "c11_06E0P6KYB5V7S5VYQA8ZTRQM4W");
  assertEquals(confusable?.suggested_canonical, "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W");
});

Deno.test("id_guard: flags non-ASCII confusable characters in span_id", () => {
  const issues = validateAttributionIds({
    span_id: "d1f8a85c-c047-422c-9951-09f4564aба3d",
  });

  assert(issues.some((i) => i.code === "span_id_non_ascii"));
  assert(issues.some((i) => i.code === "span_id_invalid_charset"));
  assert(issues.some((i) => i.code === "span_id_invalid_format"));
  assertEquals(hasIdGuardErrors(issues), true);
});
