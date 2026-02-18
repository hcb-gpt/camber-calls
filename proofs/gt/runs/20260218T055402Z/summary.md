# GT Batch Runner Report (v1)

- Run ID: `20260218T055402Z`
- Mode: `none`
- Input: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/gt/batches/gt_batch_v1_baseline86.csv`
- Output dir: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z`

## Metrics
- accuracy: `0.1512` (13/86)
- review_rate: `0.7949` (62/78)
- homeowner_override_fail_count: `0`
- staff_leak_count: `0`
- multi_project_span_count: `0`
- missing_char_offsets_count: `0`
- trigger_fail_count: `0`
- failures_count: `73`

## Diff vs Baseline
- baseline_metrics: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/baseline_preserved/20260218T054933Z/metrics.json`
- baseline_metrics_source: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T054933Z/metrics.json`
- baseline_metrics_preserved: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/baseline_preserved/20260218T054933Z/metrics.json`
- delta_accuracy: `-0.1395`
- delta_review_rate: `0.4911`
- delta_staff_leak_count: `0`
- delta_homeowner_override_fail_count: `0`
- delta_multi_project_span_count: `0`
- delta_missing_char_offsets_count: `0`

## Artifacts
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/summary.md`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/metrics.json`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/results.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/failures.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/trigger_results.csv`
- `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs/20260218T055402Z/diff.json`

## Repro
```bash
python3 scripts/gt_batch_runner.py --input /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/gt/batches/gt_batch_v1_baseline86.csv --mode none --out-root /Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/runs
```
