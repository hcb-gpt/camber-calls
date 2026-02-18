# GT Batch Runner Report (v1)

- Run ID: `20260218T052538Z`
- Mode: `reseed`
- Reseed mode: `resegment_and_reroute`
- Input: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/.temp/tier0_test_5.csv`
- Output dir: `proofs/gt/runs/20260218T052538Z`

## Metrics
- accuracy: `0.3333` (1/3)
- review_rate: `0.4` (2/5)
- homeowner_override_fail_count: `0`
- staff_leak_count: `0`
- multi_project_span_count: `0`
- missing_char_offsets_count: `0`
- trigger_fail_count: `5`
- failures_count: `2`

## Diff vs Baseline
- baseline_metrics: `proofs/gt/runs/20260218T052538Z/baseline_preserved/20260218T035851Z/metrics.json`
- baseline_metrics_source: `proofs/gt/runs/20260218T035851Z/metrics.json`
- baseline_metrics_preserved: `proofs/gt/runs/20260218T052538Z/baseline_preserved/20260218T035851Z/metrics.json`
- delta_accuracy: `0.2868`
- delta_review_rate: `-0.1`
- delta_staff_leak_count: `0`
- delta_homeowner_override_fail_count: `0`
- delta_multi_project_span_count: `0`
- delta_missing_char_offsets_count: `0`

## Artifacts
- `proofs/gt/runs/20260218T052538Z/summary.md`
- `proofs/gt/runs/20260218T052538Z/metrics.json`
- `proofs/gt/runs/20260218T052538Z/results.csv`
- `proofs/gt/runs/20260218T052538Z/failures.csv`
- `proofs/gt/runs/20260218T052538Z/trigger_results.csv`
- `proofs/gt/runs/20260218T052538Z/diff.json`

## Repro
```bash
python3 scripts/gt_batch_runner.py --input /Users/chadbarlow/gh/hcb-gpt/camber-calls/.temp/tier0_test_5.csv --mode reseed --out-root proofs/gt/runs
```
