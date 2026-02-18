# 86-Span Ground Truth Failure Taxonomy

**Date:** 2026-02-18
**Run:** `20260218T054034Z` (baseline_preserved chain)
**Model:** claude-3-haiku-20240307 / v1.12.0_world_model_facts
**Total spans evaluated:** 86
**Total failures:** 62
**Pass rate:** 27.9% (24/86)

---

## 1. Failure Category Summary

| Category | Count | % of Failures |
|---|---|---|
| review_instead_of_assign (correct project or no project) | 44 | 71.0% |
| wrong_project (misattributed to incorrect project) | 7 | 11.3% |
| span_not_found (resegmenter produced fewer spans) | 4 | 6.5% |
| none_instead_of_assign (dropped to none) | 3 | 4.8% |
| assign_instead_of_none (false positive assign) | 2 | 3.2% |
| pipeline_failure (no response returned) | 1 | 1.6% |
| eval_anomaly (decision matches but marked incorrect) | 1 | 1.6% |
| **Total** | **62** | **100%** |

The dominant failure mode (71%) is the model choosing `review` when the ground truth expects `assign`. The model correctly identifies the project in many of these cases but lacks confidence to commit.

---

## 2. Root Cause Breakdown

| Root Cause Bucket | Count | % of Failures | Key Mechanism |
|---|---|---|---|
| weak_anchor / ambiguous_contact | 30 | 48.4% | Floater contacts (5+ projects) downweighted; no strong transcript anchor found |
| bizdev_gate (bizdev_without_commitment) | 16 | 25.8% | BizDev prospect gate overrides assign even with strong evidence |
| alias_collision (wrong project via ambiguous alias) | 4 | 6.5% | Alias matches multiple projects; model picks wrong one |
| span_segmentation (span_not_found) | 4 | 6.5% | Resegmenter produced fewer spans than GT expected |
| homeowner_override_fp (false positive) | 2 | 3.2% | deterministic_homeowner_override_gate forces assign on review/null |
| blocked_project | 1 | 1.6% | "Sittler Madison" blocklist overrides correct attribution |
| junk_call_filtered | 1 | 1.6% | Low word count / single speaker turn triggers junk filter |
| other (pipeline failure, eval anomaly) | 4 | 6.5% | gt_0020 no response; gt_0042/gt_0052/gt_0089 wrong project without coded reason |
| **Total** | **62** | **100%** | |

### Root cause distribution insights

- **74.2% of failures** (46/62) stem from the model being too conservative: it sees evidence but won't commit (weak_anchor: 30, bizdev_gate: 16).
- **BizDev gate is the single highest-impact fixable cause.** Of 16 bizdev-gated failures, 7 had confidence >= 0.75 and strong transcript evidence. These would likely convert to correct assigns with a tuned gate threshold.
- **Alias collisions** are low-volume (4) but high-severity: the model confidently assigns to the wrong project.

---

## 3. BizDev Gate Deep Dive

The `bizdev_without_commitment` reason code fires when the model detects a prospect/bizdev discussion without commitment language. It forces the decision to `review` regardless of other evidence strength.

**High-confidence holds (conf >= 0.75) -- likely false gates:**

| Row ID | Confidence | Expected Project | Evidence Cited |
|---|---|---|---|
| gt_0016 | 0.900 | winship | Explicit "Winship Residence" refs, Ginger Gray contact, pavers/irrigation discussion |
| gt_0057 | 0.930 | woodbery | Client name "Shayelyn Woodbery" multiple times, journal match |
| gt_0056 | 0.850 | woodbery | "Woodbery" alias, exposed rafters discussion matches journal |
| gt_0061 | 0.850 | woodbery | Client name "Shayelyn Woodbery", project alias "Woodbery" |
| gt_0049 | 0.750 | skelton | Tub sizing discussion matches Skelton Residence open issue |
| gt_0080 | 0.750 | winship | "permit" anchor + job site context |
| gt_0030 | 0.750 | winship | Subcontractor discussion consistent with project |

These 7 spans have strong multi-signal evidence (named clients, address matches, journal corroboration) yet are blocked by the bizdev gate because the transcript also contains casual prospect language ("looking at", "thinking about", "text me").

---

## 4. Top 10 Wrong-Project / High-Impact Failure Audit

### 4.1. gt_0042 -- Bethany Rd alias collision (Woodbery -> Winship)

- **Expected:** assign to Woodbery
- **Actual:** assign to Winship Residence (conf=0.800)
- **What happened:** Transcript mentions "Bethany Rd" and "landscaping on bethany". The model resolved "Bethany Rd" to the Winship Residence address (4541 Bethany Rd). However, the GT says the span is about the Woodbery project.
- **Root cause:** "Bethany Rd" is the physical address of Winship Residence but is also mentioned in Woodbery-context calls when discussing crews moving between sites. The alias `Bethany Rd` is unambiguously mapped to Winship in the world model, but contextually the conversation was about Woodbery work logistics.
- **Fix needed:** When an address/alias matches Project A but surrounding context (crew names, materials, topics) points to Project B, flag as ambiguous rather than auto-resolving.

### 4.2. gt_0089 -- Red Oak alias collision (Permar -> Young)

- **Expected:** assign to Permar
- **Actual:** assign to Young Residence (conf=0.750)
- **What happened:** Transcript mentions "red oak" which matched the "Red Oak" alias for the Young Residence. The model treated this as a definitive anchor.
- **Root cause:** "Red oak" in this context referred to a wood species/material being discussed for the Permar project, not the Red Oak community/alias for the Young Residence. The alias system cannot distinguish material references from location references.
- **Fix needed:** Aliases derived from common nouns (materials, colors, tree species) need disambiguation logic. When "red oak" appears in a materials discussion context, it should not auto-resolve to the Young Residence alias.

### 4.3. gt_0052 -- Sparta location anchor (Woodbery -> Permar)

- **Expected:** assign to Woodbery
- **Actual:** assign to Permar Residence (conf=0.850)
- **What happened:** Transcript references "Sparta" location and cedar/cypress materials. The model matched "Sparta" to Permar Residence (located in Sparta, GA).
- **Root cause:** The Woodbery project also sources materials from Sparta-area suppliers. The geo anchor "Sparta" is overweighted relative to the broader conversation context about Woodbery materials.
- **Fix needed:** Geo-only anchors should not override when other signals (contact history, conversation flow from prior spans) point to a different project.

### 4.4. gt_0024 -- "Windships" misparse (Woodbery -> Winship)

- **Expected:** assign to Woodbery
- **Actual:** review -> Winship Residence (conf=0.740)
- **What happened:** Transcript contains "windships" which the model interpreted as a reference to "Winship Residence". The GT says this span is about Woodbery.
- **Root cause:** "Windships" is a phonetic near-match for "Winship" but in context was not a project reference. The fuzzy alias matching triggers on phonetic similarity without enough contextual validation.
- **Fix needed:** Fuzzy alias matches (edit distance > 0) should require corroborating evidence before being treated as anchors. A single fuzzy match alone should not override topic continuity from surrounding spans.

### 4.5. gt_0004 -- Homeowner override false positive (none -> assign Winship)

- **Expected:** none (no project)
- **Actual:** assign to Winship Residence (conf=0.920)
- **What happened:** The model initially decided `review` with no project (correct instinct). Then the `deterministic_homeowner_override_gate` fired, forcing assignment to Winship Residence because the caller Tony Araujo is semi-anchored to a homeowner project.
- **Root cause:** The override gate uses caller identity to force-assign to the homeowner's project even when the model's own reasoning says there is insufficient transcript evidence. It converts review/null to assign/project unconditionally.
- **Fix needed:** The homeowner override gate should respect the model's confidence and evidence assessment. If the model says "not enough evidence" (review with no project), the override should not force an assignment.

### 4.6. gt_0021 -- Homeowner override false positive (none -> assign Winship)

- **Expected:** none (no project)
- **Actual:** assign to Winship Residence (conf=0.920)
- **What happened:** Identical pattern to gt_0004. Contact Zach Givens is a drifter. Model correctly identified insufficient evidence (review/null). Homeowner override gate forced assign to Winship.
- **Root cause:** Same as gt_0004. The deterministic override ignores the model's evidence assessment.

### 4.7. gt_0012 -- Door/hinge discussion (Winship -> Woodbery Barns)

- **Expected:** assign to Winship
- **Actual:** review -> Woodbery Barns (conf=0.650)
- **What happened:** Transcript discusses door and hinge issues plus Carter Lumber. Model matched to Woodbery Barns because contact Jimmy Chastain is associated with that project as a drifter.
- **Root cause:** The drifter contact signal was given more weight than the cross-span context. This is span_index:1 in a multi-span call where span_index:0 was also about Winship-related door work.
- **Fix needed:** Cross-span continuity should be factored in. When adjacent spans discuss the same topic (doors), prior span attribution should inform the current span.

### 4.8. gt_0045 -- Grout/paver discussion (Winship -> Woodbery Residence)

- **Expected:** assign to Winship
- **Actual:** review -> Woodbery Residence (conf=0.750)
- **What happened:** Transcript discusses grout color and pavers. Model matched to Woodbery Residence based on contact John Singleton's association with that project.
- **Root cause:** Pavers/hardscape work was active on both Winship and Woodbery. The drifter contact pushed the model toward the wrong project.
- **Fix needed:** When a topic (pavers) is active on multiple projects, the model should flag ambiguity rather than picking the contact's most common project.

### 4.9. gt_0067 -- Walkway/Luis reference (Winship -> Woodbery Residence)

- **Expected:** assign to Winship
- **Actual:** review -> Woodbery Residence (conf=0.850)
- **What happened:** Transcript mentions a walkway, "Randy", and "Luis". Model matched "Luis Juarez" to Woodbery Residence.
- **Root cause:** Luis Juarez works on both projects. The model resolved the contact to a single project without checking if the walkway context matches Winship (where walkway work was also active).
- **Fix needed:** Multi-project contacts should not be treated as single-project anchors. When a contact works on 2+ candidate projects, both should be presented as possibilities.

### 4.10. gt_0035 -- Blocked project override (Permar -> none)

- **Expected:** assign to Permar
- **Actual:** none (conf=0.000)
- **What happened:** The `blocked_project` rule for "Sittler Madison" overrode the attribution entirely, setting the result to none.
- **Root cause:** The blocklist is too broad. "Sittler Madison" catches calls that are legitimately about other projects (Permar) when Zack Sittler is on the call and Madison, GA is mentioned.
- **Fix needed:** Blocklist rules should be scoped more narrowly. A blocked project should only suppress attribution to that specific project, not suppress all attribution when the blocked terms appear.

---

## 5. Recommendations

### Recommendation A: Lower BizDev Gate for High-Evidence Candidates

**Problem:** The `bizdev_without_commitment` gate blocks 16 spans (25.8% of failures). Of these, 7 have confidence >= 0.75 with strong corroborating evidence (named clients, address matches, journal context).

**Proposed fix:** Add an evidence-strength override to the BizDev gate:
- If confidence >= 0.75 AND the model cites 3+ corroborating signals (any combination of: named client match, address/alias match, journal context match, anchored contact), bypass the BizDev gate and allow the assign decision.
- If confidence < 0.75 OR fewer than 3 corroborating signals, the BizDev gate continues to hold.

**Expected impact:** Recovers 7 of 16 bizdev-gated failures (estimated +7 correct assigns, +8.1% absolute pass rate improvement).

### Recommendation B: Fix Alias Disambiguation for Multi-Match Cases

**Problem:** 4 wrong-project failures (gt_0042, gt_0089, gt_0052, gt_0024) result from aliases that match multiple projects or are contextually ambiguous.

**Proposed fix:**
1. When an alias/anchor matches multiple candidate projects (e.g., "Bethany Rd" is both an address and a cross-project reference), flag the attribution as `ambiguous` and include both candidates in the response.
2. Distinguish material/common-noun aliases from proper-noun aliases. "Red oak" as a wood species should not auto-resolve to the "Red Oak" community alias. Add a `noun_type` field to the alias table (`proper_noun`, `common_noun`, `geo`) and require common-noun aliases to have corroborating context.
3. Require fuzzy alias matches (edit distance > 0, like "windships" -> "Winship") to have at least one additional corroborating signal before being treated as anchors.

**Expected impact:** Eliminates 4 wrong-project failures (estimated +4 correct assigns or correct ambiguity flags, +4.7% absolute pass rate improvement). Also reduces false confidence in alias-driven attributions across the board.

---

## Appendix: Full Failure Roster by Category

### review_instead_of_assign (44 spans)
gt_0005, gt_0006, gt_0007, gt_0008, gt_0009, gt_0010, gt_0011, gt_0013, gt_0014, gt_0015, gt_0016, gt_0017, gt_0022, gt_0023, gt_0028, gt_0029, gt_0030, gt_0031, gt_0037, gt_0043, gt_0046, gt_0047, gt_0049, gt_0050, gt_0051, gt_0056, gt_0057, gt_0061, gt_0062, gt_0069, gt_0070, gt_0071, gt_0072, gt_0073, gt_0074, gt_0075, gt_0076, gt_0077, gt_0078, gt_0079, gt_0080, gt_0083, gt_0085, gt_0087

### wrong_project (7 spans)
gt_0012, gt_0024, gt_0042, gt_0045, gt_0052, gt_0067, gt_0089

### span_not_found (4 spans)
gt_0032, gt_0033, gt_0034, gt_0081

### none_instead_of_assign (3 spans)
gt_0035, gt_0058, gt_0084

### assign_instead_of_none (2 spans)
gt_0004, gt_0021

### pipeline_failure (1 span)
gt_0020

### eval_anomaly (1 span)
gt_0059
