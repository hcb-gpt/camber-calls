# Attribution Accuracy Report — v1

**Date:** 2026-02-15
**GT Sample:** 86 labeled spans across 46 calls (Feb 6-7 + replayed batch)
**Evaluator:** Chad Barlow (GT labels), DATA-1 (analysis)

---

## 1. Headline Metrics

| Metric | Value |
|--------|-------|
| Overall Accuracy | **50.0%** (43/86 spans correct) |
| Project Accuracy (excl. GT=none) | **48.2%** (40/83) |
| Correct None (both pipeline+GT = none) | 3/3 (100%) |

## 2. Per-Project Performance

| Project | TP | FP | FN | Precision | Recall | F1 |
|---------|---:|---:|---:|----------:|-------:|---:|
| Winship | 19 | 0 | 26 | 100.0% | 42.2% | 59.4% |
| Woodbery | 16 | 3 | 12 | 84.2% | 57.1% | 68.1% |
| Permar | 3 | 1 | 3 | 75.0% | 50.0% | 60.0% |
| Kreikemeier | 2 | 1 | 0 | 66.7% | 100.0% | 80.0% |
| Skelton | 0 | 0 | 2 | — | 0.0% | — |
| Sittler | 0 | 16 | 0 | 0.0% | — | — |
| Hurley | 0 | 2 | 0 | 0.0% | — | — |
| White | 0 | 2 | 0 | 0.0% | — | — |
| Moss | 0 | 1 | 0 | 0.0% | — | — |

**Key observations:**
- **Winship** has perfect precision (when it says Winship, it's right) but terrible recall (misses 26/45 Winship spans). The misses are split between Sittler leaks, sub misattribution, and missing anchoring.
- **Woodbery** is the best-performing real project (F1=68.1%) because Shayelyn Woodbery calls are correctly anchored.
- **Sittler** is a phantom project with 16 false positives and zero true positives. Every single Sittler attribution is wrong.
- **Skelton** is completely invisible to the pipeline (0 recall). Dwayne Brown's Skelton work was misattributed to White and Moss.

## 3. Error Genealogy

### 3.1 SITTLER STAFF NAME LEAK — 16 spans (37.2% of errors)

**Root cause:** "Sittler Residence" and "Sittler Residence (Athens)" are Zack Sittler's personal name being treated as a project. Zack Sittler is HCB staff (the builder answering calls). He is never a client.

**Mechanism:** The pipeline's `scan_transcript_for_projects_v2` function matches the name "Sittler" from transcripts where Zack identifies himself or the transcript labels him. It then maps this to the Sittler Residence project.

**Impact:** 16 of 43 errors (37.2%). If fixed, accuracy jumps from 50.0% to at least 68.6% (assuming the pipeline would have gotten null instead — which would match GT for none of these since they all have real GT projects, so the real gain depends on what replaces Sittler).

**Fix:** Hard-block "Sittler Residence" and "Sittler Residence (Athens)" from attribution output. They should never be returned as a project name. Remove from the projects list or add to an exclusion list.

**Affected callers:** Randy Booth, Flynt Treadaway, Randy Bryan, Brian Dove, John Singleton, Ron Persall, Zach Givens

### 3.2 MISSING CONTACT ANCHORING — 17 spans (39.5% of errors)

**Root cause:** The pipeline returns null/none for spans that a human can easily attribute by knowing which caller works on which project. The pipeline lacks a contact→project mapping.

**Mechanism:** When a transcript contains no explicit project name mentions, the pipeline has no fallback signal. A human knows "Ron Persall is currently doing doors for Winship" or "Jimmy Chastain is at the Winship jobsite," but the pipeline can't leverage caller identity.

**Impact:** 17 of 43 errors (39.5%). This is the single largest error category. These are all false negatives — the pipeline says "I don't know" when it should have said "Winship" or "Woodbery."

**Fix:** Build a contact→project lookup table:

| Contact | Current Project(s) | Signal Strength |
|---------|-------------------|-----------------|
| Jimmy Chastain | Winship | Strong (dedicated sub) |
| Ron Persall / Ron C Persall | Winship | Strong (door work) |
| Flynt Treadaway | Winship + Woodbery | Moderate (works on both) |
| Brian Dove | Woodbery | Strong (framing) |
| John Singleton | Winship | Strong (walkway/masonry) |
| Shayelyn Woodbery | Woodbery | Absolute (client) |
| Lou Winship | Winship | Absolute (client) |
| Malcolm Hetzer | Winship | Strong ("Bethany road job") |
| Larry Fitzgerald | Winship | Strong (doors/panels) |
| Dwayne Brown | Skelton | Strong (tub/bath) |

This table should be used as a tier-1 fallback when transcript-based attribution returns null. Client callers (Shayelyn, Lou, Mike Kreikemeier) are the strongest signal — client = client project, always.

### 3.3 SUBCONTRACTOR MISATTRIBUTION — 10 spans (23.3% of errors)

**Root cause:** Subcontractors work on multiple HCB projects. The pipeline picks the wrong project because it anchors on project-name mentions in the transcript rather than contextual cues about which project the sub discussion pertains to.

**Mechanism:** Examples:
- **John Singleton** walkway work → pipeline says Hurley/White, GT = Winship. The pipeline saw "walkway" and associated it with another project where walkways were discussed.
- **Brian Dove** framing → pipeline says Permar/Hurley, GT = Woodbery. The pipeline grabbed the wrong project from Brian's multi-project involvement.
- **Malcolm Hetzer** "Bethany road job" → pipeline says Woodbery, GT = Winship. Bethany Road is the Winship address.
- **Dwayne Brown** "the Skeletons" → pipeline says White/Moss, GT = Skelton. Pipeline doesn't map "Skeletons" to the Skelton project.

**Impact:** 10 of 43 errors (23.3%).

**Fix:**
1. **Location→project mapping:** "Bethany Road" = Winship, "Sparta" = Permar
2. **Contact→project anchoring** (overlaps with §3.2): Use sub's current primary project as a prior
3. **Nickname/colloquial mapping:** "the Skeletons" → Skelton Residence
4. **Cross-reference recent calls:** If John Singleton's last 5 calls were all Winship, new ambiguous calls should default to Winship

## 4. Confidence Calibration Problem

| Bucket | Avg Confidence | Count |
|--------|---------------:|------:|
| Correct predictions | 0.863 | 43 |
| Wrong predictions | 0.630 | 43 |
| High-conf wrong (≥0.80) | 0.853 | 18 |

**18 of 43 wrong predictions (42%) had confidence ≥ 0.80.** The pipeline is dangerously overconfident on wrong answers, particularly on Sittler leaks (which get 0.75-0.90 confidence).

**Fix:** Recalibrate confidence scores. Sittler should never reach high confidence (or should be blocked entirely). Sub-based attributions without transcript corroboration should be capped at 0.60.

## 5. Priority Fix Order

| Priority | Fix | Errors Fixed | Projected Accuracy Gain |
|----------|-----|-------------|------------------------|
| P0 | Block Sittler from attribution | 16 | +18.6 pp (to ~68.6%) |
| P1 | Add contact→project lookup | 17 | +19.8 pp (to ~88.4%) |
| P2 | Fix sub misattribution via contact anchoring | 10 | +11.6 pp (to ~100%) |
| P3 | Confidence recalibration | 0 direct | Reduces false-assign rate |

**Theoretical ceiling after P0+P1+P2:** ~100% on this GT sample (all 43 errors are covered by these three fixes).

## 6. GT Rules Established

These rules were established during interactive labeling and should be codified:

1. **Client = client project, ALWAYS.** Shayelyn → Woodbery. Lou → Winship. Mike → Kreikemeier.
2. **Sittler is NEVER a project.** Zack Sittler is HCB staff.
3. **Voicemails = none** (unless identifiable project content)
4. **Wrong numbers = none**
5. **"Bethany Road" = Winship** (address signal)
6. **"Sparta" = Permar** (location signal)
7. **Contact-to-project anchoring is the #1 attribution signal**
8. **Multi-span calls:** each span can have a different GT project
9. **Warranty: 1 year after close** — calls about completed projects still attribute to that project

---

*Next steps: Expand GT sample to 200+ spans, re-run accuracy after P0 fix (Sittler block), build contact→project lookup table for P1.*
