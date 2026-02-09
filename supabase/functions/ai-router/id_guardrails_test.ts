import { normalizeIdsForAttribution } from "./id_guardrails.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected=${String(expected)} actual=${String(actual)}`);
  }
}

Deno.test("id guardrail: canonicalizes OCR-confusable interaction_id prefix c11_ -> cll_", () => {
  const out = normalizeIdsForAttribution({
    span_id: "d1f8a85c-c047-422c-9951-09f4564aba3d",
    interaction_id: "c11_06E0P6KYB5V7S5VYQA8ZTRQM4W",
  });

  assertEquals(
    out.interaction_id,
    "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W",
    "interaction_id should be canonicalized",
  );
  assert(
    out.warnings.some((w) => w.code === "interaction_id_confusable_prefix"),
    "expected interaction_id_confusable_prefix warning",
  );
  assertEquals(
    out.raw_interaction_id,
    "c11_06E0P6KYB5V7S5VYQA8ZTRQM4W",
    "raw interaction_id should be preserved",
  );
});

Deno.test("id guardrail: canonicalizes non-ASCII confusable characters inside span UUID", () => {
  const out = normalizeIdsForAttribution({
    span_id: "d1f8a85c-c047-422c-9951-09f4564a\u0431\u04303d",
    interaction_id: "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W",
  });

  assertEquals(
    out.span_id,
    "d1f8a85c-c047-422c-9951-09f4564aba3d",
    "span_id should be canonicalized to valid UUID",
  );
  assert(
    out.warnings.some((w) => w.code === "span_id_confusable_chars_mapped"),
    "expected span_id_confusable_chars_mapped warning",
  );
  assert(
    out.warnings.some((w) => w.code === "span_id_canonicalized"),
    "expected span_id_canonicalized warning",
  );
});

Deno.test("id guardrail: valid IDs pass without warnings", () => {
  const out = normalizeIdsForAttribution({
    span_id: "d1f8a85c-c047-422c-9951-09f4564aba3d",
    interaction_id: "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W",
  });

  assertEquals(out.span_id, "d1f8a85c-c047-422c-9951-09f4564aba3d", "valid span_id should remain unchanged");
  assertEquals(out.interaction_id, "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W", "valid interaction_id should remain unchanged");
  assertEquals(out.warnings.length, 0, "expected no warnings for valid IDs");
});
