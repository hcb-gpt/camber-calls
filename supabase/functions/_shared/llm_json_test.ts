import { assertEquals } from "https://deno.land/std@0.218.0/assert/mod.ts";
import { parseLlmJson } from "./llm_json.ts";

Deno.test("parseLlmJson parses strict JSON unchanged", () => {
  const raw = '{"decision":"assign","confidence":0.91,"anchors":[]}';
  const parsed = parseLlmJson<{ decision: string }>(raw);

  assertEquals(parsed.parseMode, "strict");
  assertEquals(parsed.value.decision, "assign");
});

Deno.test("parseLlmJson sanitizes unescaped control chars in JSON strings", () => {
  const raw = '{"decision":"review","reasoning":"bad\ncontrol\tchars"}';
  const parsed = parseLlmJson<{ decision: string; reasoning: string }>(raw);

  assertEquals(parsed.parseMode, "sanitized");
  assertEquals(parsed.value.decision, "review");
  assertEquals(parsed.value.reasoning, "badcontrolchars");
});
