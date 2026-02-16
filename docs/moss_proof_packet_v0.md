# Moss Residence World Model -- Project A Proof Packet (v0)

**Status:** TEMPLATE (to be filled by DEV after seed + GT run)
**Date:** 2026-02-16
**Owner:** STRAT-1 (design) / DEV (execution) / DATA (measurement)
**Pilot project_id:** `47cb7720-9495-4187-8220-a8100c3b67aa`
**Pilot project name:** Moss Residence

---

## Supporting Files

| Document | Path | Purpose |
|----------|------|---------|
| GT Evaluation Protocol | `docs/moss_gt_evaluation_protocol_v0.md` | Full before/after evaluation runbook |
| Replication Recipe | `docs/world_model_project_recipe_v0.md` | How to add a new project to the world model |
| Seed SQL | `scripts/backfills/moss_residence_seed_v0.sql` | 33-fact seed script with provenance |
| Provenance hygiene check | `scripts/sql/proofs/project_facts_missing_provenance.sql` | Detect orphan facts (no evidence_event_id) |
| NOW-leakage check | `scripts/sql/proofs/project_facts_now_leakage_template.sql` | Verify KNOWN_AS_OF filtering |
| Seed counts by kind | `scripts/sql/proofs/project_facts_seed_counts_by_kind.sql` | Verify fact landing by kind |
| Window counts | `scripts/sql/proofs/project_facts_window_counts.sql` | Count facts by time window |

---

## Acceptance Criteria (4 Artifacts Required)

This proof packet must contain completed versions of all four artifacts below.
Each artifact has a **PASS/FAIL** gate. All four must PASS for Project A acceptance.

| # | Artifact | Gate |
|---|----------|------|
| 1 | Seed Counts / Provenance Checks | 33 facts, 100% provenance, 0 orphans |
| 2 | Example Context Pack | project_facts appear in context_package when WORLD_MODEL_FACTS_ENABLED=true |
| 3 | Attribution Improved by Facts | At least one span moved review->assign or was corrected |
| 4 | GT Before/After Slice | Accuracy improvement on Moss interactions; sentinel checks pass |

---

## ARTIFACT 1: Seed Counts and Provenance Checks

### Purpose

Prove that the 33 facts from `moss_residence_seed_v0.sql` landed in `project_facts` with 100% provenance (every row has a valid `evidence_event_id` linking to an `evidence_events` row).

### 1.1 Fact Count by Kind

**Query:**

```sql
-- Artifact 1.1: Seed counts by fact_kind for Moss
SELECT
  fact_kind,
  count(*) AS fact_count,
  count(*) FILTER (WHERE evidence_event_id IS NOT NULL) AS with_evidence,
  count(*) FILTER (WHERE evidence_event_id IS NULL) AS without_evidence,
  round(
    100.0 * count(*) FILTER (WHERE evidence_event_id IS NOT NULL) / count(*),
    1
  ) AS provenance_pct
FROM public.project_facts
WHERE project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
GROUP BY fact_kind
ORDER BY fact_kind;
```

**Expected Output:**

| fact_kind | fact_count | with_evidence | without_evidence | provenance_pct |
|-----------|-----------|---------------|-----------------|----------------|
| scope.contact | 3 | 3 | 0 | 100.0 |
| scope.dimension | 13 | 13 | 0 | 100.0 |
| scope.feature | 4 | 4 | 0 | 100.0 |
| scope.material | 8 | 8 | 0 | 100.0 |
| scope.site | 5 | 5 | 0 | 100.0 |
| **TOTAL** | **33** | **33** | **0** | **100.0** |

**Actual Output:**

```
<< DEV: paste query output here >>
```

**PASS/FAIL:** `____`

### 1.2 Provenance Hygiene (Zero Orphans)

**Query:**

```sql
-- Artifact 1.2: Orphan facts check (must return 0)
SELECT count(*) AS orphan_facts
FROM public.project_facts
WHERE project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
  AND evidence_event_id IS NULL;
```

**Expected Output:** `0`

**Actual Output:**

```
<< DEV: paste query output here >>
```

**PASS/FAIL:** `____`

### 1.3 Evidence Event Integrity

**Query:**

```sql
-- Artifact 1.3: Evidence event back-reference integrity
SELECT
  e.evidence_event_id,
  e.source_type,
  e.source_id,
  e.occurred_at_utc,
  e.metadata->>'seed_script' AS seed_script,
  e.metadata->>'project_code' AS project_code,
  count(pf.*) AS fact_count
FROM public.evidence_events e
JOIN public.project_facts pf ON pf.evidence_event_id = e.evidence_event_id
WHERE pf.project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
GROUP BY e.evidence_event_id, e.source_type, e.source_id, e.occurred_at_utc, e.metadata
ORDER BY e.occurred_at_utc DESC;
```

**Expected Output:**

| evidence_event_id | source_type | source_id | seed_script | project_code | fact_count |
|-------------------|-------------|-----------|-------------|--------------|------------|
| (uuid) | manual | manual_seed:moss_residence_v0:... | scripts/backfills/moss_residence_seed_v0.sql | MOSS | 33 |

- Exactly 1 evidence_events row.
- `source_type` = `manual`.
- `source_id` starts with `manual_seed:moss_residence_v0:`.
- `fact_count` = 33.

**Actual Output:**

```
<< DEV: paste query output here >>
```

**PASS/FAIL:** `____`

### 1.4 as_of_at Consistency

**Query:**

```sql
-- Artifact 1.4: All Moss facts share the same as_of_at
SELECT
  as_of_at,
  count(*) AS fact_count
FROM public.project_facts
WHERE project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
GROUP BY as_of_at;
```

**Expected Output:**

| as_of_at | fact_count |
|----------|-----------|
| 2025-09-01 04:00:00+00 | 33 |

All facts must share `as_of_at = 2025-09-01T04:00:00Z` (conservative estimate before any Moss calls).

**Actual Output:**

```
<< DEV: paste query output here >>
```

**PASS/FAIL:** `____`

### Artifact 1 Summary

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| Total fact count | 33 | `____` | `____` |
| Provenance coverage | 100% | `____` | `____` |
| Orphan facts | 0 | `____` | `____` |
| Evidence events rows | 1 | `____` | `____` |
| Evidence fact_count | 33 | `____` | `____` |
| as_of_at uniform | 2025-09-01T04:00:00Z | `____` | `____` |

**Artifact 1 overall:** `PASS / FAIL`

---

## ARTIFACT 2: Example Context Pack

### Purpose

Prove that when `WORLD_MODEL_FACTS_ENABLED=true`, the ai-router context_package for a Moss-relevant call includes `project_facts` data. This demonstrates the facts flow from DB into the LLM prompt.

### 2.1 Prerequisite Check

**Query:**

```sql
-- Artifact 2.1: Confirm WORLD_MODEL_FACTS_ENABLED is exercised
-- (Check that project_facts exist for Moss before running the context pack test)
SELECT count(*) AS moss_facts_available
FROM public.project_facts
WHERE project_id = '47cb7720-9495-4187-8220-a8100c3b67aa';
```

**Expected:** `33`

**Actual:**

```
<< DEV: paste query output here >>
```

### 2.2 Context Pack Extraction

Pick one Moss interaction from the GT manifest. Reseed it with `dry_run=true` and capture the context_package from the ai-router logs or response.

**Interaction selected:** `____` (interaction_id)
**WORLD_MODEL_FACTS_ENABLED:** `true` (confirmed on ai-router Edge Function)

**Command:**

```bash
# Reseed a single Moss interaction in dry_run mode to capture context pack
curl -s -X POST "${SUPABASE_URL}/functions/v1/admin-reseed" \
  -H "Content-Type: application/json" \
  -H "x-edge-secret: ${EDGE_SHARED_SECRET}" \
  -d '{
    "interaction_id": "<INTERACTION_ID>",
    "mode": "reseed_and_close_loop",
    "reason": "proof_packet_context_pack_check",
    "dry_run": true
  }' | python3 -m json.tool
```

### 2.3 Evidence: project_facts in Context Package

From the context_package output or ai-router logs, extract the section showing project_facts injected for Moss.

**Expected format in prompt context (from `buildWorldModelFactsCandidateSummary`):**

```
--- World Model Facts for candidate: Moss Residence ---
[scope.site] as_of=2025-09-01 observed=<date> fact=site.address.city: Bishop
[scope.dimension] as_of=2025-09-01 observed=<date> fact=dimension.sqft_heated_total: 4213
[scope.feature] as_of=2025-09-01 observed=<date> fact=feature.foundation_type: Crawlspace (block)
```

**Actual context pack excerpt (paste the relevant section):**

```
<< DEV: paste the world model facts section from the context_package here >>
```

### 2.4 Verification Checks

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| project_facts section present in context_package | yes | `____` | `____` |
| Facts shown are for Moss project_id | `47cb7720-...` | `____` | `____` |
| Fact count in context (capped at max_per_project) | <= 20 | `____` | `____` |
| Same-call exclusion respected (no facts from this interaction) | yes | `____` | `____` |
| as_of dates visible in fact lines | yes | `____` | `____` |

**Artifact 2 overall:** `PASS / FAIL`

---

## ARTIFACT 3: Attribution Improved by Facts

### Purpose

Demonstrate at least one concrete span where world model facts changed the attribution outcome for the better: either upgrading a stuck `review` to a correct `assign`, or correcting a misattribution.

### 3.1 Candidate Span Selection

**Query to find spans where the decision changed between baseline and post-seed:**

```sql
-- Artifact 3.1: Find Moss spans where decision changed after fact seeding
-- Requires two runs: baseline (before facts) and post-seed (after facts)
-- Compare the latest attribution for each span across both runs

WITH moss_spans AS (
  SELECT
    cs.id AS span_id,
    cs.interaction_id,
    cs.span_index,
    left(cs.transcript_segment, 150) AS transcript_preview
  FROM conversation_spans cs
  WHERE cs.is_superseded = false
    AND cs.interaction_id IN (
      SELECT DISTINCT interaction_id
      FROM interactions
      WHERE project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
    )
),
baseline_attr AS (
  -- Attributions from BEFORE fact seeding
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.decision AS baseline_decision,
    sa.confidence AS baseline_confidence,
    p.name AS baseline_project,
    sa.attributed_at AS baseline_attributed_at
  FROM span_attributions sa
  LEFT JOIN projects p ON p.id = sa.project_id
  WHERE sa.attributed_at < '<SEED_TIMESTAMP>'
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST, sa.id DESC
),
postseed_attr AS (
  -- Attributions from AFTER fact seeding + reseed
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.decision AS postseed_decision,
    sa.confidence AS postseed_confidence,
    p.name AS postseed_project,
    sa.attributed_at AS postseed_attributed_at
  FROM span_attributions sa
  LEFT JOIN projects p ON p.id = sa.project_id
  WHERE sa.attributed_at >= '<SEED_TIMESTAMP>'
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST, sa.id DESC
)
SELECT
  ms.interaction_id,
  ms.span_index,
  ms.transcript_preview,
  ba.baseline_decision,
  ba.baseline_confidence,
  ba.baseline_project,
  pa.postseed_decision,
  pa.postseed_confidence,
  pa.postseed_project,
  CASE
    WHEN ba.baseline_decision = 'review' AND pa.postseed_decision = 'assign'
      THEN 'UPGRADED'
    WHEN ba.baseline_decision = 'assign' AND pa.postseed_decision = 'review'
      THEN 'DOWNGRADED'
    WHEN ba.baseline_project != pa.postseed_project
      THEN 'PROJECT_CHANGED'
    ELSE 'STABLE'
  END AS change_type,
  pa.postseed_confidence - ba.baseline_confidence AS confidence_delta
FROM moss_spans ms
LEFT JOIN baseline_attr ba ON ba.span_id = ms.span_id
LEFT JOIN postseed_attr pa ON pa.span_id = ms.span_id
WHERE ba.baseline_decision IS DISTINCT FROM pa.postseed_decision
   OR ba.baseline_project IS DISTINCT FROM pa.postseed_project
ORDER BY ms.interaction_id, ms.span_index;
```

Replace `<SEED_TIMESTAMP>` with the UTC timestamp of the `COMMIT` run of `moss_residence_seed_v0.sql`.

**Actual Output:**

```
<< DEV: paste query output here >>
```

### 3.2 Selected Example (Detailed Walkthrough)

Pick the single best example of an attribution improvement. Fill in the following.

**Interaction ID:** `____`
**Span Index:** `____`
**Transcript excerpt (first 200 chars):**

```
<< DEV: paste transcript segment excerpt >>
```

**Baseline Attribution (before facts):**

| Field | Value |
|-------|-------|
| decision | `____` |
| project | `____` |
| confidence | `____` |
| reason_codes | `____` |
| world_model_facts_in_context | `false` |

**Post-Seed Attribution (after facts):**

| Field | Value |
|-------|-------|
| decision | `____` |
| project | `____` |
| confidence | `____` |
| reason_codes | `____` |
| world_model_facts_in_context | `true` |
| world_model_references | `____` |

**What changed and why:**

```
<< DEV: explain which facts corroborated the attribution and how the outcome improved >>
```

### 3.3 Verification

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| At least 1 span changed decision or project | yes | `____` | `____` |
| The change is an improvement (matches GT) | yes | `____` | `____` |
| world_model_facts_in_context = true in post-seed | yes | `____` | `____` |
| Specific facts cited in world_model_references | yes | `____` | `____` |

**Artifact 3 overall:** `PASS / FAIL`

---

## ARTIFACT 4: GT Before/After Slice

### Purpose

Show aggregate accuracy improvement on Moss interactions, and pass all sentinel checks from the GT evaluation protocol (Section B.3 of `moss_gt_evaluation_protocol_v0.md`).

### 4.1 Run Metadata

| Field | Baseline Run | Post-Seed Run |
|-------|-------------|---------------|
| run_id | `____` | `____` |
| run_timestamp (UTC) | `____` | `____` |
| manifest | `gt_manifest_moss_pilot_v0.csv` | `gt_manifest_moss_pilot_v0.csv` |
| total spans evaluated | `____` | `____` |
| pipeline version | `____` | `____` |
| WORLD_MODEL_FACTS_ENABLED | `false` | `true` |
| project_facts count for Moss | 0 | 33 |
| seed script SHA | n/a | `____` |

### 4.2 Headline Metrics Comparison

**Query (run against both baseline and post-seed summary.json, or compute from rows.jsonl):**

```sql
-- Artifact 4.2: Headline metrics for a single GT run
-- Run this twice: once for baseline attributions, once for post-seed attributions
-- Adjust the attributed_at filter to isolate each run window

WITH gt_manifest AS (
  -- Load from gt_manifest_moss_pilot_v0.csv
  -- Each row: interaction_id, span_index, expected_project, expected_decision
  SELECT * FROM (VALUES
    -- << DEV: INSERT GT MANIFEST ROWS HERE >>
    -- ('cll_...', 0, 'moss_residence', 'assign'),
    -- ('cll_...', 1, 'none', 'none'),
    ('placeholder'::text, 0::int, 'placeholder'::text, 'placeholder'::text)
  ) AS v(interaction_id, span_index, expected_project, expected_decision)
),
moss_spans AS (
  SELECT
    cs.id AS span_id,
    cs.interaction_id,
    cs.span_index
  FROM conversation_spans cs
  WHERE cs.is_superseded = false
    AND cs.interaction_id IN (SELECT interaction_id FROM gt_manifest)
),
latest_attr AS (
  SELECT DISTINCT ON (sa.span_id)
    sa.span_id,
    sa.decision,
    sa.confidence,
    p.name AS predicted_project,
    sa.applied_project_id,
    sa.needs_review
  FROM span_attributions sa
  LEFT JOIN projects p ON p.id = sa.project_id
  WHERE sa.attributed_at BETWEEN '<RUN_WINDOW_START>' AND '<RUN_WINDOW_END>'
  ORDER BY sa.span_id, sa.attributed_at DESC NULLS LAST, sa.id DESC
),
scored AS (
  SELECT
    ms.interaction_id,
    ms.span_index,
    gm.expected_project,
    gm.expected_decision,
    la.predicted_project,
    la.decision AS predicted_decision,
    la.confidence,
    CASE
      WHEN lower(gm.expected_project) = lower(la.predicted_project)
       AND gm.expected_decision = la.decision
      THEN true
      ELSE false
    END AS correct,
    CASE
      WHEN la.decision = 'assign'
       AND lower(gm.expected_project) != lower(la.predicted_project)
      THEN true
      ELSE false
    END AS misattributed
  FROM moss_spans ms
  JOIN gt_manifest gm ON gm.interaction_id = ms.interaction_id
    AND gm.span_index = ms.span_index
  LEFT JOIN latest_attr la ON la.span_id = ms.span_id
)
SELECT
  count(*) AS total_spans,
  round(100.0 * count(*) FILTER (WHERE predicted_decision = 'review') / count(*), 1)
    AS review_rate_pct,
  round(100.0 * count(*) FILTER (WHERE predicted_decision = 'assign') / count(*), 1)
    AS assign_rate_pct,
  round(100.0 * count(*) FILTER (WHERE predicted_decision = 'none') / count(*), 1)
    AS none_rate_pct,
  round(100.0 * count(*) FILTER (WHERE correct) / count(*), 1)
    AS overall_accuracy_pct,
  count(*) FILTER (WHERE misattributed) AS misattribution_count,
  round(avg(confidence) FILTER (WHERE correct), 3)
    AS mean_confidence_correct,
  round(avg(confidence) FILTER (WHERE NOT correct), 3)
    AS mean_confidence_incorrect
FROM scored;
```

**Expected Output Format:**

| Metric | Baseline | Post-Seed | Delta | Gate |
|--------|----------|-----------|-------|------|
| total_spans | `____` | `____` | -- | -- |
| review_rate (%) | ~78% | `____` | `____` pp | decrease >= 10pp |
| assign_rate (%) | ~22% | `____` | `____` pp | increase |
| none_rate (%) | `____` | `____` | `____` pp | -- |
| overall_accuracy (%) | `____` | `____` | `____` pp | no regression |
| misattribution_count | `____` | `____` | `____` | <= baseline |
| mean_confidence (correct) | `____` | `____` | `____` | increase desired |
| mean_confidence (incorrect) | `____` | `____` | `____` | decrease desired |

**Actual Baseline Output:**

```
<< DEV: paste baseline headline metrics >>
```

**Actual Post-Seed Output:**

```
<< DEV: paste post-seed headline metrics >>
```

### 4.3 Sentinel Checks

These are binary PASS/FAIL checks required by the GT evaluation protocol (Section B.3).

#### CHECK-1: Hurley Misattribution Corrected

- **Call:** `cll_06E0P6KYB5V7S5VYQA8ZTRQM4W`
- **Baseline:** attributed to Moss (WRONG)
- **GT:** Hurley
- **PASS condition:** post-seed attribution is NOT Moss (ideally Hurley, or review)
- **Rationale:** World model facts for Moss (Bishop GA, crawlspace foundation, McKenzie Drafting) should NOT corroborate a Hancock County / Hurley call.

**Query:**

```sql
-- CHECK-1: Hurley misattribution sentinel
SELECT
  cs.interaction_id,
  cs.span_index,
  sa.decision,
  p.name AS predicted_project,
  sa.confidence,
  sa.attributed_at
FROM conversation_spans cs
JOIN span_attributions sa ON sa.span_id = cs.id
LEFT JOIN projects p ON p.id = sa.project_id
WHERE cs.interaction_id = 'cll_06E0P6KYB5V7S5VYQA8ZTRQM4W'
  AND cs.is_superseded = false
  AND sa.attributed_at >= '<POSTSEED_RUN_START>'
ORDER BY cs.span_index, sa.attributed_at DESC
LIMIT 5;
```

**Expected:** `predicted_project` != 'Moss Residence'
**Actual:**

```
<< DEV: paste output >>
```

**CHECK-1:** `PASS / FAIL`

---

#### CHECK-2: Winship/Moss Confusion Corrected

- **Call:** `cll_06E09H1BF9R1VAGJ6ZGBSRY3E8`
- **Baseline:** attributed to Moss@0.75 (WRONG; Chris Gaugler = roofing sub = Winship project)
- **GT:** Winship
- **PASS condition:** post-seed attribution is NOT Moss
- **Rationale:** Moss facts (Bishop GA, crawlspace, McKenzie Drafting) are phase-incongruent with a roofing sub call. The guardrail should detect the lack of corroboration.

**Query:**

```sql
-- CHECK-2: Winship/Moss confusion sentinel
SELECT
  cs.interaction_id,
  cs.span_index,
  sa.decision,
  p.name AS predicted_project,
  sa.confidence,
  sa.attributed_at
FROM conversation_spans cs
JOIN span_attributions sa ON sa.span_id = cs.id
LEFT JOIN projects p ON p.id = sa.project_id
WHERE cs.interaction_id = 'cll_06E09H1BF9R1VAGJ6ZGBSRY3E8'
  AND cs.is_superseded = false
  AND sa.attributed_at >= '<POSTSEED_RUN_START>'
ORDER BY cs.span_index, sa.attributed_at DESC
LIMIT 5;
```

**Expected:** `predicted_project` != 'Moss Residence'
**Actual:**

```
<< DEV: paste output >>
```

**CHECK-2:** `PASS / FAIL`

---

#### CHECK-3: Weak Anchor Upgrade Rate

- **Population:** all Moss spans where baseline reason_code includes `llm_weak_anchor`
- **PASS condition:** at least 30% of these spans move from `review` to `assign` with correct project
- **Rationale:** Facts provide the "strong anchor" that was previously missing

**Query:**

```sql
-- CHECK-3: Weak anchor upgrade rate
-- Requires joining baseline and post-seed rows on (interaction_id, span_index)
-- from the eval harness output files (rows.jsonl)

-- Manual computation:
-- weak_anchor_baseline_count = << count of spans with llm_weak_anchor in baseline >>
-- upgraded_correct_count = << count of those that became assign + correct in post-seed >>
-- upgrade_rate = upgraded_correct_count / weak_anchor_baseline_count
```

**Weak anchor baseline count:** `____`
**Upgraded to correct assign:** `____`
**Upgrade rate:** `____` %

**CHECK-3:** `PASS / FAIL` (threshold: >= 30%)

---

#### CHECK-4: No New Misattributions Introduced

- **Population:** all spans in the GT manifest
- **PASS condition:** `post_seed_misattribution_count <= baseline_misattribution_count`
- **Rationale:** Facts should reduce misattributions, not create new ones.

**Baseline misattribution count:** `____`
**Post-seed misattribution count:** `____`
**Delta:** `____`

**CHECK-4:** `PASS / FAIL`

---

#### CHECK-5: Staff-Name Leak Class Absent

- **PASS condition:** `staff_leak_rate == 0` in post-seed run
- **Rationale:** Staff name blocklisting was a prior fix; facts should not re-introduce this failure class.

**Query:**

```sql
-- CHECK-5: Staff name leak check
-- staff_names = names from the contacts/people table that are staff, not projects
SELECT count(*) AS staff_leak_count
FROM span_attributions sa
JOIN projects p ON p.id = sa.project_id
WHERE sa.span_id IN (
  SELECT cs.id FROM conversation_spans cs
  WHERE cs.interaction_id IN (
    -- << INSERT MOSS GT INTERACTION IDS >>
  )
  AND cs.is_superseded = false
)
AND sa.attributed_at >= '<POSTSEED_RUN_START>'
AND lower(p.name) IN (
  -- << INSERT KNOWN STAFF NAMES >>
);
```

**Staff leak count:** `____`

**CHECK-5:** `PASS / FAIL`

---

#### CHECK-6: No NOW-Leakage in Fact Retrieval

- **PASS condition:** all facts used in context packs satisfy KNOWN_AS_OF(t_call) filtering
- **Rationale:** World model architecture v0 (Section 2.2 N2 of the architecture doc) requires KNOWN_AS_OF as default. Facts must not include future knowledge relative to the call timestamp.

**Query (run per interaction):**

```sql
-- CHECK-6: NOW-leakage template
-- From: scripts/sql/proofs/project_facts_now_leakage_template.sql
-- Replace $1 with interaction_id

SELECT
  pf.id AS fact_id,
  pf.fact_kind,
  pf.fact_payload->>'feature' AS feature,
  pf.as_of_at AS fact_as_of,
  i.created_at AS call_timestamp,
  CASE
    WHEN pf.as_of_at <= i.created_at THEN 'AS_OF'
    ELSE 'POST_HOC'
  END AS temporal_status
FROM public.project_facts pf
CROSS JOIN (
  SELECT created_at FROM public.interactions
  WHERE interaction_id = '<INTERACTION_ID>'
) i
WHERE pf.project_id = '47cb7720-9495-4187-8220-a8100c3b67aa'
  AND pf.as_of_at > i.created_at;
```

**Expected:** 0 rows (no facts have `as_of_at` after the call timestamp)

**Actual row count:** `____`

**CHECK-6:** `PASS / FAIL`

---

### 4.4 Per-Span Decision Change Summary

Computed from joining baseline `rows.jsonl` and post-seed `rows.jsonl` on `(interaction_id, span_index)`.

| Category | Count | Percentage |
|----------|-------|-----------|
| Upgraded (review/none -> correct assign) | `____` | `____` % |
| Downgraded (assign -> review/none) | `____` | `____` % |
| Stable correct | `____` | `____` % |
| Stable incorrect | `____` | `____` % |
| Regressed (correct -> incorrect) | `____` | `____` % |
| **Total spans** | `____` | 100% |

### 4.5 Sentinel Check Summary

| Check | Description | Result | Evidence |
|-------|------------|--------|----------|
| CHECK-1 | Hurley misattribution corrected | `____` | `____` |
| CHECK-2 | Winship/Moss confusion corrected | `____` | `____` |
| CHECK-3 | Weak anchor upgrade rate >= 30% | `____` | `____` % |
| CHECK-4 | No new misattributions | `____` | delta = `____` |
| CHECK-5 | Staff leak rate == 0 | `____` | count = `____` |
| CHECK-6 | No NOW-leakage | `____` | post_hoc = `____` |

**Artifact 4 overall:** `PASS / FAIL`

---

## Final Acceptance Gate

| Artifact | Description | Status |
|----------|------------|--------|
| 1 | Seed Counts / Provenance (33 facts, 100% provenance) | `____` |
| 2 | Context Pack (project_facts in context_package) | `____` |
| 3 | Attribution Improved (at least 1 span improved) | `____` |
| 4 | GT Before/After (accuracy up, sentinels pass) | `____` |

### Primary Success Gate (from GT Evaluation Protocol Section C.1)

| Criterion | Threshold | Actual | Status |
|-----------|-----------|--------|--------|
| review_rate decreases | >= 10pp reduction | `____` pp | `____` |
| assign_accuracy does not regress | >= baseline | `____` | `____` |
| misattribution_count does not increase | <= baseline | `____` | `____` |
| CHECK-1 (Hurley) passes | not Moss | `____` | `____` |
| CHECK-4 (no new misattrib) passes | 0 regressions | `____` | `____` |
| CHECK-5 (staff leak) passes | rate == 0 | `____` | `____` |
| CHECK-6 (NOW-leakage) passes | 0 post_hoc | `____` | `____` |

### Secondary Indicators (desirable, not blocking)

| Indicator | Target | Actual | Status |
|-----------|--------|--------|--------|
| Confidence calibration improves | fewer high-conf-wrong | `____` | `____` |
| Weak anchor upgrade rate | >= 30% (CHECK-3) | `____` | `____` |
| assign_rate increases | > baseline | `____` | `____` |
| confidence_delta > 0 for correct spans | positive | `____` | `____` |
| CHECK-2 (Winship) passes | not Moss | `____` | `____` |
| J0 contamination rate | 0 | `____` | `____` |

---

## Recommendation

`SHIP / ITERATE / REVERT`

```
<< DEV: provide rationale based on gate results above >>
```

---

## Appendix: Execution Log

| Step | Timestamp (UTC) | Executor | Notes |
|------|----------------|----------|-------|
| Baseline snapshot captured | `____` | `____` | run_id: `____` |
| Seed SQL dry-run (ROLLBACK) | `____` | `____` | errors: `____` |
| Seed SQL applied (COMMIT) | `____` | `____` | 33 facts inserted |
| WORLD_MODEL_FACTS_ENABLED set | `____` | `____` | confirmed on ai-router |
| Post-seed reseed run | `____` | `____` | run_id: `____` |
| Proof packet filled | `____` | `____` | this document |

---

*Template version: v0. Generated from GT evaluation protocol, replication recipe, and seed SQL.*
*Seed SQL: scripts/backfills/moss_residence_seed_v0.sql (33 facts, 5 kinds, 1 evidence_event)*
*GT protocol: docs/moss_gt_evaluation_protocol_v0.md (6 sentinel checks, 7 primary gates)*
