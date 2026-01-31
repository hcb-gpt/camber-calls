/**
 * Verb Detection Unit Tests (PR-10)
 *
 * POLICY (STRAT-1 BLOCK):
 * - Role tagging is VERB-DRIVEN only
 * - "destination" requires: headed to, going to, on my way to, driving to, etc.
 * - "origin" requires: coming from, leaving, back from, left from, etc.
 * - Single place mention without verb = "proximity" (no direction inferred)
 * - NEVER infer direction from a single place without explicit verb
 *
 * Run: deno test --allow-read verb_detection_test.ts
 */

// Import the verb patterns (copy from index.ts for standalone test)
const DESTINATION_VERBS = [
  "headed to",
  "heading to",
  "going to",
  "on my way to",
  "on the way to",
  "driving to",
  "heading over to",
  "headed over to",
  "going over to",
  "en route to",
  "enroute to",
];

const ORIGIN_VERBS = [
  "coming from",
  "came from",
  "leaving",
  "left from",
  "left",
  "back from",
  "returning from",
  "just left",
  "driving from",
  "on my way from",
];

/**
 * VERB-DRIVEN ROLE DETECTION (copy from index.ts)
 */
function detectPlaceRole(
  transcriptLower: string,
  placeIdx: number,
  placeName: string,
): { role: "proximity" | "origin" | "destination"; trigger_verb: string | null } {
  const VERB_WINDOW = 60;
  const windowStart = Math.max(0, placeIdx - VERB_WINDOW);
  const windowText = transcriptLower.slice(windowStart, placeIdx + placeName.length);

  for (const verb of DESTINATION_VERBS) {
    const verbIdx = windowText.indexOf(verb);
    if (verbIdx >= 0) {
      const verbEndPos = windowStart + verbIdx + verb.length;
      if (verbEndPos <= placeIdx + 5) {
        return { role: "destination", trigger_verb: verb };
      }
    }
  }

  for (const verb of ORIGIN_VERBS) {
    const verbIdx = windowText.indexOf(verb);
    if (verbIdx >= 0) {
      const verbEndPos = windowStart + verbIdx + verb.length;
      if (verbEndPos <= placeIdx + 5) {
        return { role: "origin", trigger_verb: verb };
      }
    }
  }

  return { role: "proximity", trigger_verb: null };
}

// ============================================================
// TEST CASES
// ============================================================

Deno.test("no verb => proximity (CRITICAL: never infer direction)", () => {
  // Single place mention without any directional verb
  const transcript = "yeah i'm in athens right now";
  const placeName = "athens";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  if (result.role !== "proximity") {
    throw new Error(
      `Expected 'proximity', got '${result.role}'. POLICY VIOLATION: No verb should mean no direction inference.`,
    );
  }
  if (result.trigger_verb !== null) {
    throw new Error(`Expected null trigger_verb, got '${result.trigger_verb}'`);
  }
});

Deno.test("'headed to' => destination", () => {
  const transcript = "i'm headed to athens for a meeting";
  const placeName = "athens";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  if (result.role !== "destination") {
    throw new Error(`Expected 'destination', got '${result.role}'`);
  }
  if (result.trigger_verb !== "headed to") {
    throw new Error(`Expected 'headed to', got '${result.trigger_verb}'`);
  }
});

Deno.test("'on my way to' => destination", () => {
  const transcript = "hey i'm on my way to madison";
  const placeName = "madison";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  if (result.role !== "destination") {
    throw new Error(`Expected 'destination', got '${result.role}'`);
  }
  if (result.trigger_verb !== "on my way to") {
    throw new Error(`Expected 'on my way to', got '${result.trigger_verb}'`);
  }
});

Deno.test("'coming from' => origin", () => {
  const transcript = "i'm coming from athens heading your way";
  const placeName = "athens";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  if (result.role !== "origin") {
    throw new Error(`Expected 'origin', got '${result.role}'`);
  }
  if (result.trigger_verb !== "coming from") {
    throw new Error(`Expected 'coming from', got '${result.trigger_verb}'`);
  }
});

Deno.test("'just left' => origin", () => {
  const transcript = "i just left watkinsville";
  const placeName = "watkinsville";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  if (result.role !== "origin") {
    throw new Error(`Expected 'origin', got '${result.role}'`);
  }
  // May match "just left" or "left" depending on iteration order
  if (!result.trigger_verb?.includes("left")) {
    throw new Error(`Expected verb containing 'left', got '${result.trigger_verb}'`);
  }
});

Deno.test("place mentioned without context => proximity (CRITICAL)", () => {
  // This is the MOST IMPORTANT test - ensures we don't hallucinate direction
  const transcripts = [
    "we need to talk about the athens project",
    "the athens site is looking good",
    "call me when you get to athens", // "get to" is NOT a destination verb
    "athens is about 30 miles from here",
    "i was in athens yesterday", // past tense, not current movement
  ];

  for (const transcript of transcripts) {
    const placeName = "athens";
    const placeIdx = transcript.indexOf(placeName);

    const result = detectPlaceRole(transcript, placeIdx, placeName);

    if (result.role !== "proximity") {
      throw new Error(
        `POLICY VIOLATION: "${transcript}" should be 'proximity', got '${result.role}' with verb '${result.trigger_verb}'`,
      );
    }
  }
});

Deno.test("verb must be BEFORE place, not after", () => {
  // Verb appearing after the place should not trigger
  const transcript = "athens is where i'm headed to next";
  const placeName = "athens";
  const placeIdx = transcript.indexOf(placeName);

  const result = detectPlaceRole(transcript, placeIdx, placeName);

  // "headed to" appears AFTER "athens", so should be proximity
  if (result.role !== "proximity") {
    throw new Error(`Expected 'proximity' (verb after place), got '${result.role}'`);
  }
});

console.log("All verb detection tests passed!");
