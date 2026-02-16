import { assert, assertEquals } from "https://deno.land/std@0.218.0/assert/mod.ts";
import { evaluateJunkCallPrefilter, normalizeDurationSeconds } from "./junk_call_prefilter.ts";

Deno.test("normalizeDurationSeconds handles seconds and milliseconds", () => {
  assertEquals(normalizeDurationSeconds(12), 12);
  assertEquals(normalizeDurationSeconds(12_400), 12);
  assertEquals(normalizeDurationSeconds("19"), 19);
  assertEquals(normalizeDurationSeconds(""), null);
  assertEquals(normalizeDurationSeconds(-2), null);
});

Deno.test("evaluateJunkCallPrefilter flags voicemail transcript", () => {
  const result = evaluateJunkCallPrefilter({
    transcript: "Hi, please leave a message after the tone. Mailbox is full.",
  });
  assertEquals(result.isJunk, true);
  assert(result.reasonCodes.includes("junk_call_filtered"));
  assert(result.reasonCodes.includes("voicemail_pattern"));
});

Deno.test("evaluateJunkCallPrefilter flags low-signal short call", () => {
  const result = evaluateJunkCallPrefilter({
    transcript: "Can you hear me now? Bad service. Call dropped.",
    durationSeconds: 9,
  });
  assertEquals(result.isJunk, true);
  assert(result.reasonCodes.includes("connection_failure_pattern"));
  assert(result.reasonCodes.includes("short_duration"));
});

Deno.test("evaluateJunkCallPrefilter fails open for substantive short transcript", () => {
  const result = evaluateJunkCallPrefilter({
    transcript: "Can you send the estimate and schedule install tomorrow?",
    durationSeconds: 12,
  });
  assertEquals(result.isJunk, false);
});
