/**
 * gmail-context-lookup extraction tests
 *
 * Run:
 *   deno test supabase/functions/gmail-context-lookup/extraction_test.ts
 */

interface AliasRow {
  alias: string;
  project_id: string | null;
}

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertEqual(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}\nexpected=${JSON.stringify(expected)}\nactual=${JSON.stringify(actual)}`);
  }
}

function safeArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function uniqStrings(values: unknown[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const str = String(value || "").trim();
    if (!str) continue;
    const low = str.toLowerCase();
    if (seen.has(low)) continue;
    seen.add(low);
    out.push(str);
  }
  return out;
}

function findMentions(
  text: string,
  aliases: AliasRow[],
): { project_mentions: string[]; mentioned_project_ids: string[] } {
  const hayLower = String(text || "").toLowerCase();
  const matches: Array<{ alias: string; project_id: string | null }> = [];
  const seen = new Set<string>();
  const isWordChar = (ch: string) => /[a-z0-9]/i.test(ch);

  for (const row of aliases) {
    const alias = String(row?.alias || "").trim();
    if (!alias) continue;
    const aliasLower = alias.toLowerCase();
    if (aliasLower.length < 3) continue;

    const idx = hayLower.indexOf(aliasLower);
    if (idx < 0) continue;

    const before = idx === 0 ? " " : hayLower[idx - 1];
    const afterIdx = idx + aliasLower.length;
    const after = afterIdx >= hayLower.length ? " " : hayLower[afterIdx];
    if (isWordChar(before) || isWordChar(after)) continue;

    const key = `${aliasLower}|${String(row?.project_id || "").toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);

    matches.push({
      alias,
      project_id: row?.project_id ? String(row.project_id) : null,
    });
  }

  return {
    project_mentions: matches.map((m) => m.alias),
    mentioned_project_ids: uniqStrings(matches.map((m) => m.project_id)).filter(Boolean),
  };
}

function extractAmounts(text: string): string[] {
  const raw = String(text || "");
  const regex = /\$(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*(?:k|K)?/g;
  const matches = raw.match(regex) || [];
  return uniqStrings(matches).slice(0, 10);
}

function extractSubjectKeywords(subject: string | null, stopwords: Set<string>): string[] {
  const lower = String(subject || "").toLowerCase();
  if (!lower.trim()) return [];

  const tokens = lower
    .replace(/[^a-z0-9]+/g, " ")
    .split(/\s+/)
    .map((t) => t.trim())
    .filter(Boolean);

  const out: string[] = [];
  const seen = new Set<string>();
  for (const token of tokens) {
    if (token.length < 3) continue;
    if (stopwords.has(token)) continue;
    if (seen.has(token)) continue;
    seen.add(token);
    out.push(token);
    if (out.length >= 12) break;
  }
  return out;
}

Deno.test("findMentions: word boundary aware and deduped", () => {
  const aliases: AliasRow[] = [
    { alias: "Winship", project_id: "p1" },
    { alias: "Ship", project_id: "p2" },
    { alias: "Madison Heights", project_id: "p3" },
  ];

  const text = "Need update on Winship and Madison Heights. winship is delayed.";
  const result = findMentions(text, aliases);

  assertEqual(result.project_mentions, ["Winship", "Madison Heights"], "project_mentions mismatch");
  assertEqual(result.mentioned_project_ids, ["p1", "p3"], "project_id list mismatch");
});

Deno.test("findMentions: does not match inside larger words", () => {
  const aliases: AliasRow[] = [{ alias: "ship", project_id: "p-ship" }];
  const text = "The transshipment status was updated.";
  const result = findMentions(text, aliases);
  assertEqual(result.project_mentions, [], "should not match substring inside larger word");
});

Deno.test("extractAmounts: captures canonical currency patterns", () => {
  const amounts = extractAmounts("Budget is $47,500 and maybe $50k, not $50000 plain text.");
  assertEqual(amounts, ["$47,500", "$50k", "$50000"], "amount extraction mismatch");
});

Deno.test("extractSubjectKeywords: strips stopwords and dedupes", () => {
  const stopwords = new Set(["re", "fw", "and", "for", "update"]);
  const keywords = extractSubjectKeywords("RE: Update for Winship And Budget Review", stopwords);
  assertEqual(keywords, ["winship", "budget", "review"], "subject keyword extraction mismatch");
});

Deno.test("safeArray helper baseline", () => {
  assertEqual(safeArray<number>([1, 2, 3]), [1, 2, 3], "safeArray should keep arrays");
  assertEqual(safeArray<number>(null), [], "safeArray should guard non-arrays");
  assert(safeArray<number>(undefined).length === 0, "safeArray should return empty for undefined");
});
