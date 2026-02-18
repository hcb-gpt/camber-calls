# GT Batch Runner Report (v1)

- Run ID: `20260218T054242Z`
- Mode: `none`
- Input: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/gt/batches/gt_batch_v1_baseline86.csv`
- Output dir: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z`

## Metrics
- accuracy: `0.2791` (24/86)
- review_rate: `0.5926` (48/81)
- homeowner_override_fail_count: `0`
- staff_leak_count: `0`
- multi_project_span_count: `0`
- missing_char_offsets_count: `0`
- trigger_fail_count: `0`
- failures_count: `62`

## Diff vs Baseline
- baseline_metrics: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/baseline_preserved/20260218T053045Z/metrics.json`
- baseline_metrics_source: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T053045Z/metrics.json`
- baseline_metrics_preserved: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/baseline_preserved/20260218T053045Z/metrics.json`
- delta_accuracy: `-0.0542`
- delta_review_rate: `-0.0074`
- delta_staff_leak_count: `0`
- delta_homeowner_override_fail_count: `0`
- delta_multi_project_span_count: `0`
- delta_missing_char_offsets_count: `0`

## Artifacts
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/summary.md`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/metrics.json`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/results.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/failures.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/trigger_results.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054242Z/diff.json`

## Repro
```bash
python3 scripts/gt_batch_runner.py --input /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/gt/batches/gt_batch_v1_baseline86.csv --mode none --out-root /Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs
```
