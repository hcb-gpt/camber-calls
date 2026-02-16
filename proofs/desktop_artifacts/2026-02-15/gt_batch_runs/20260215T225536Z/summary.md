# GT Batch Runner Report (v1)

- Run ID: `20260215T225536Z`
- Mode: `none`
- Input: `/Users/chadbarlow/gh/hcb-gpt/.worktrees/camber-calls-dev1-homeowner-override/tests/fixtures/gt_batch_v1_smoke.csv`
- Output dir: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z`

## Metrics
- accuracy: `1.0` (10/10)
- review_rate: `0.8` (8/10)
- homeowner_override_fail_count: `0`
- staff_leak_count: `5`
- multi_project_span_count: `0`
- missing_char_offsets_count: `0`
- trigger_fail_count: `0`
- failures_count: `0`

## Diff vs Baseline
- baseline_metrics: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/baseline_preserved/20260215T221308Z/metrics.json`
- baseline_metrics_source: `/Users/chadbarlow/gh/hcb-gpt/_artifacts_local/2026-02-15/desktop_moved/gt_batch_runs/20260215T221308Z/metrics.json`
- baseline_metrics_preserved: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/baseline_preserved/20260215T221308Z/metrics.json`
- delta_accuracy: `0.6`
- delta_review_rate: `0.1`
- delta_staff_leak_count: `5`
- delta_homeowner_override_fail_count: `0`
- delta_multi_project_span_count: `0`
- delta_missing_char_offsets_count: `0`

## Artifacts
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/summary.md`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/metrics.json`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/results.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/failures.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/trigger_results.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T225536Z/diff.json`

## Repro
```bash
python3 scripts/gt_batch_runner.py --input /Users/chadbarlow/gh/hcb-gpt/.worktrees/camber-calls-dev1-homeowner-override/tests/fixtures/gt_batch_v1_smoke.csv --mode none --out-root /Users/chadbarlow/Desktop/gt_batch_runs
```
