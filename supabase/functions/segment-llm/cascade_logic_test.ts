import { assertEquals } from "https://deno.land/std@0.218.0/assert/mod.ts";

interface Segment {
  span_index: number;
  char_start: number;
  char_end: number;
}

function segmentsAgreeWithinTolerance(
  a: Segment[],
  b: Segment[],
  toleranceChars: number,
): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const startDiff = Math.abs(a[i].char_start - b[i].char_start);
    const endDiff = Math.abs(a[i].char_end - b[i].char_end);
    if (startDiff > toleranceChars || endDiff > toleranceChars) return false;
  }
  return true;
}

function fallbackSplitCount(transcriptLength: number): number {
  return transcriptLength < 5000 ? 2 : transcriptLength < 10000 ? 3 : 4;
}

function disagreementScore(segmentCount: number, warningCount: number): number {
  return (segmentCount * 10) - warningCount;
}

Deno.test("segment cascade: boundary tolerance accepts close matches", () => {
  const openai = [
    { span_index: 0, char_start: 0, char_end: 1000 },
    { span_index: 1, char_start: 1000, char_end: 2000 },
  ];
  const anthropic = [
    { span_index: 0, char_start: 0, char_end: 1030 },
    { span_index: 1, char_start: 1030, char_end: 2000 },
  ];

  assertEquals(segmentsAgreeWithinTolerance(openai, anthropic, 40), true);
  assertEquals(segmentsAgreeWithinTolerance(openai, anthropic, 10), false);
});

Deno.test("segment cascade: mismatch segment counts never agree", () => {
  const a = [{ span_index: 0, char_start: 0, char_end: 1000 }];
  const b = [
    { span_index: 0, char_start: 0, char_end: 500 },
    { span_index: 1, char_start: 500, char_end: 1000 },
  ];
  assertEquals(segmentsAgreeWithinTolerance(a, b, 100), false);
});

Deno.test("segment fallback: deterministic split count scales by transcript length", () => {
  assertEquals(fallbackSplitCount(2100), 2);
  assertEquals(fallbackSplitCount(7600), 3);
  assertEquals(fallbackSplitCount(12000), 4);
});

Deno.test("segment disagreement scoring prefers more structure with fewer warnings", () => {
  const openaiScore = disagreementScore(3, 1); // 29
  const anthropicScore = disagreementScore(2, 0); // 20
  assertEquals(openaiScore > anthropicScore, true);
});
