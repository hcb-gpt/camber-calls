# GT Batch Runner Report (v1)

- Run ID: `20260215T221308Z`
- Mode: `shadow`
- Input: `/Users/chadbarlow/gh/hcb-gpt/.worktrees/camber-calls-dev1-homeowner-override/tests/fixtures/gt_batch_v1_smoke.csv`
- Output dir: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z`

## Metrics
- accuracy: `0.4` (4/10)
- review_rate: `0.7` (7/10)
- homeowner_override_fail_count: `0`
- staff_leak_count: `0`
- multi_project_span_count: `0`
- missing_char_offsets_count: `0`
- trigger_fail_count: `0`
- failures_count: `6`

## Artifacts
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z/summary.md`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z/metrics.json`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z/results.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z/failures.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z/trigger_results.csv`

## Repro
```bash
python3 scripts/gt_batch_runner.py --input /Users/chadbarlow/gh/hcb-gpt/.worktrees/camber-calls-dev1-homeowner-override/tests/fixtures/gt_batch_v1_smoke.csv --mode shadow --out-root /Users/chadbarlow/Desktop/gt_batch_runs
```
