export type ParseMode = "strict" | "sanitized" | "synthetic";

export interface ParsedLlmJson<T> {
  value: T;
  parseMode: ParseMode;
}

export function stripCodeFences(raw: string): string {
  return (raw || "").replace(/```json\n?/gi, "").replace(/```\n?/g, "").trim();
}

export function stripControlChars(s: string): string {
  return s.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "");
}

export function removeTrailingCommas(s: string): string {
  return s.replace(/,\s*([}\]])/g, "$1");
}

export function parseLlmJson<T>(raw: string, options: { fallbackKey?: string } = {}): ParsedLlmJson<T> {
  const cleaned = stripCodeFences(raw);
  const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
  const jsonText = jsonMatch ? jsonMatch[0] : cleaned;

  const attempts: Array<{ parseMode: ParseMode; value: string }> = [
    { parseMode: "strict", value: jsonText },
    { parseMode: "sanitized", value: removeTrailingCommas(stripControlChars(jsonText)) },
  ];

  if (options.fallbackKey) {
    const key = options.fallbackKey.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pattern = new RegExp(`"${key}"\\s*:\\s*\\[[\\s\\S]*?\\]`, "i");
    const match = cleaned.match(pattern);
    if (match?.[0]) {
      attempts.push({
        parseMode: "synthetic",
        value: `{${match[0]}}`,
      });
    }
  }

  for (const attempt of attempts) {
    try {
      return { value: JSON.parse(attempt.value) as T, parseMode: attempt.parseMode };
    } catch {
      continue;
    }
  }

  throw new Error(`json_parse_failed: could not parse LLM output (${raw.length} chars)`);
}
