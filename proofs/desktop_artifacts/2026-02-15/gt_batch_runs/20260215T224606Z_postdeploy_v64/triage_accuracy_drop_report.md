# Post-Deploy Accuracy Drop Triage (0.40 -> 0.30)

## Scope
- Analyzed failures from: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64/failures.csv`
- Failure rows: `7`

## Top 3 Failure Patterns (by tag/cause)
1. `weak_or_ambiguous_evidence` (`6/7`)
- Rows: `smoke_02, smoke_04, smoke_05, smoke_06, smoke_08, smoke_10`
- Signal: reason codes repeatedly include `weak_anchor` + `ambiguous_contact` (plus some `quote_unverified`).
- Hypothesis: retrieval/context grounding is too weak for confident project attribution on floater-heavy calls.
- Next fix: retrieval/evidence lane
  - require at least one high-confidence anchor (contact/project journal/address match) before assignment,
  - otherwise deterministically force `review` with explicit reason code.

2. `project_resolution_failures` (`5/7`)
- Rows: `smoke_04, smoke_05, smoke_06, smoke_08, smoke_10`
- Signal: expected project missing (`actual_project_id` empty) or wrong project chosen (often expected non-Winship -> actual Winship).
- Hypothesis: project ranking favors broad lexical overlap over deterministic homeowner/contact constraints in ambiguous transcripts.
- Next fix: deterministic gate lane
  - apply stronger homeowner/project hard filters before final ranking,
  - enforce explicit negative checks for conflicting homeowner anchors,
  - add a tie-break rule that rejects ambiguous top-1 matches into `review`.

3. `decision_outcome_mismatches` (`3/7`)
- Rows: `smoke_02, smoke_06, smoke_09`
- Signal: expected `review` but actual was `none`, blank, or `assign`.
- Hypothesis: decision policy is not consistently conservative when evidence is mixed/partial.
- Next fix: decision policy lane
  - tighten decision threshold for `assign`,
  - map weak evidence bundles (`weak_anchor`, `ambiguous_contact`, `quote_unverified`) to deterministic `review`.

## Baseline Retention Lock (Runner Hygiene)
Implemented in runner source:
- `/Users/chadbarlow/gh/hcb-gpt/.worktrees/camber-calls-dev1-homeowner-override/scripts/gt_batch_runner.py`

Changes:
- Explicit `--baseline` path now fails fast if missing.
- Baseline artifacts are copied into each run at:
  - `<run_dir>/baseline_preserved/<baseline_run_id>/...`
- `diff.json` + `summary.md` now include concrete baseline references:
  - `baseline_metrics_source`
  - `baseline_metrics_preserved`

Validation proof run:
- Run dir: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z`
- Preserved baseline: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/baseline_preserved/20260215T221308Z/metrics.json`
- Diff file: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/diff.json`

## Recommended Next Fix Order
1. Deterministic homeowner/project gating upgrades (highest leverage for wrong-project cases).
2. Retrieval/evidence scoring hardening for floater-heavy transcripts.
3. Decision-threshold tightening to force `review` under weak evidence.
