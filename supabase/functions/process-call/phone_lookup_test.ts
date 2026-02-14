import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { normalizePhoneForLookup } from "./phone_lookup.ts";

Deno.test("normalizePhoneForLookup strips non-digits", () => {
  assertEquals(normalizePhoneForLookup("(512) 555-0199"), "5125550199");
});

Deno.test("normalizePhoneForLookup keeps last 10 digits when input is longer", () => {
  assertEquals(normalizePhoneForLookup("+1 (512) 555-0199"), "5125550199");
  assertEquals(normalizePhoneForLookup("15125550199"), "5125550199");
});

Deno.test("normalizePhoneForLookup returns null for empty input", () => {
  assertEquals(normalizePhoneForLookup(null), null);
  assertEquals(normalizePhoneForLookup(""), null);
});
