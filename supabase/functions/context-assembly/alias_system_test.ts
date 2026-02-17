import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const WOODBERY_PROJECT_ID = "7db5e186-7dda-4c2c-b85e-7235b67e06d8";

// ---------------------------------------------------------------------------
// Test 1: v_project_alias_lookup returns unified aliases
// ---------------------------------------------------------------------------
Deno.test(
  "v_project_alias_lookup returns unified aliases for Woodbery",
  async () => {
    const { data, error } = await db
      .from("v_project_alias_lookup")
      .select("project_id, alias")
      .eq("project_id", WOODBERY_PROJECT_ID);

    assertEquals(error, null, `Query failed: ${JSON.stringify(error)}`);
    assertExists(data);
    assertEquals(
      data.length > 0,
      true,
      "Expected at least 1 alias row for Woodbery",
    );

    for (const row of data!) {
      assertExists(row.project_id, "Row missing project_id");
      assertExists(row.alias, "Row missing alias");
    }
  },
);

// ---------------------------------------------------------------------------
// Test 2: promote_alias round-trip
// ---------------------------------------------------------------------------
Deno.test("promote_alias round-trip", async () => {
  const testAlias = "test_alias_" + Date.now();

  // 1. Insert a test suggestion
  const { data: inserted, error: insertErr } = await db
    .from("suggested_aliases")
    .insert({
      project_id: WOODBERY_PROJECT_ID,
      alias: testAlias,
      status: "pending",
      source: "test_harness",
    })
    .select("id")
    .single();

  assertEquals(insertErr, null, `Insert failed: ${JSON.stringify(insertErr)}`);
  assertExists(inserted);
  const suggestionId = inserted!.id;

  try {
    // 2. Call RPC: promote_alias
    const { error: rpcErr } = await db.rpc("promote_alias", {
      p_suggestion_id: suggestionId,
      p_reviewed_by: "test_harness",
    });
    assertEquals(rpcErr, null, `RPC failed: ${JSON.stringify(rpcErr)}`);

    // 3. Verify: suggested_aliases status = 'approved'
    const { data: suggestion, error: fetchErr } = await db
      .from("suggested_aliases")
      .select("status")
      .eq("id", suggestionId)
      .single();

    assertEquals(fetchErr, null, `Fetch failed: ${JSON.stringify(fetchErr)}`);
    assertEquals(
      suggestion?.status,
      "approved",
      "Suggestion should be approved after promote",
    );

    // 4. Verify: project_aliases has new row with matching alias
    const { data: aliasRow, error: aliasErr } = await db
      .from("project_aliases")
      .select("id, alias")
      .eq("project_id", WOODBERY_PROJECT_ID)
      .eq("alias", testAlias);

    assertEquals(aliasErr, null, `Alias fetch failed: ${JSON.stringify(aliasErr)}`);
    assertExists(aliasRow);
    assertEquals(
      aliasRow!.length > 0,
      true,
      "Expected project_aliases to contain the promoted alias",
    );
  } finally {
    // 5. Cleanup: DELETE the test suggestion and project alias
    await db
      .from("project_aliases")
      .delete()
      .eq("project_id", WOODBERY_PROJECT_ID)
      .eq("alias", testAlias);

    await db
      .from("suggested_aliases")
      .delete()
      .eq("id", suggestionId);
  }
});

// ---------------------------------------------------------------------------
// Test 3: retire_aliases_for_closed_projects
// ---------------------------------------------------------------------------
Deno.test(
  "retire_aliases_for_closed_projects returns count",
  async () => {
    const { data, error } = await db.rpc(
      "retire_aliases_for_closed_projects",
    );

    assertEquals(error, null, `RPC failed: ${JSON.stringify(error)}`);
    assertExists(data);
    assertEquals(typeof data.ok, "boolean", "Expected ok to be boolean");
    assertEquals(data.ok, true, "Expected ok = true");
    assertEquals(
      typeof data.retired_count,
      "number",
      "Expected retired_count to be a number",
    );
    assertEquals(
      Array.isArray(data.affected_project_ids),
      true,
      "Expected affected_project_ids to be an array",
    );
  },
);

// ---------------------------------------------------------------------------
// Helper: findTermInText (inlined copy for testing)
// ---------------------------------------------------------------------------
function findTermInText(textLower: string, termLower: string): number {
  const idx = textLower.indexOf(termLower);
  if (idx < 0) return -1;
  const before = idx === 0 ? " " : textLower[idx - 1];
  const afterIdx = idx + termLower.length;
  const after = afterIdx >= textLower.length ? " " : textLower[afterIdx];
  const isWordChar = (ch: string) => /[a-z0-9]/i.test(ch);
  if (isWordChar(before)) return -1;
  if (isWordChar(after)) return -1;
  if (after === "'" || after === "\u2019") {
    const nextIdx = afterIdx + 1;
    if (nextIdx < textLower.length && textLower[nextIdx].toLowerCase() === "s") {
      const afterS = nextIdx + 1;
      if (afterS >= textLower.length || !isWordChar(textLower[afterS])) {
        return idx;
      }
    }
    return -1;
  }
  return idx;
}

// ---------------------------------------------------------------------------
// Test 4: findTermInText apostrophe handling
// ---------------------------------------------------------------------------
Deno.test(
  "findTermInText handles possessive apostrophes correctly",
  () => {
    // Possessive = valid match
    const r1 = findTermInText("skelton's house", "skelton");
    assertEquals(
      r1 >= 0,
      true,
      "Possessive 's should count as a valid match",
    );

    // Mid-word apostrophe = not a boundary
    const r2 = findTermInText("o'neal called", "neal");
    assertEquals(
      r2,
      -1,
      "Mid-word apostrophe should NOT be a word boundary",
    );

    // Normal word boundary
    const r3 = findTermInText("the skelton project", "skelton");
    assertEquals(r3 >= 0, true, "Normal word boundary should match");

    // Curly quote possessive
    const r4 = findTermInText("at skelton\u2019s place", "skelton");
    assertEquals(
      r4 >= 0,
      true,
      "Curly quote possessive should count as valid match",
    );

    // No boundary after term (substring without boundary)
    const r5 = findTermInText("skeltons building", "skelton");
    assertEquals(
      r5,
      -1,
      "No boundary after term should NOT match",
    );
  },
);
