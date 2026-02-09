# Temporal Backtest Report

- Generated (UTC): 2026-02-08T21:55:28Z
- Holdout start (UTC): 2026-01-25T21:55:28Z
- Latest interactions evaluated: 51
- With resolved review labels: 37

## Prompt Metrics

| Prompt | Labeled | Precision | Recall | Abstain | Correction | Hard-Neg Labeled | Hard-Neg Precision |
|---|---:|---:|---:|---:|---:|---:|---:|
| v1.5.0 | 37 | 100% | 18.75% | 75.67567567567568% | 0% | 6 | n/a |

## Failure Buckets

- Corrected assignments: 0
- Abstained but positive resolution: 26
- Assigned with negative resolution: 0
- Hard-negative count: 9

## Delta (Baseline -> Latest)

Not available (single prompt version in holdout window).

## Repro Commands

```bash
cd /Users/chadbarlow/gh/hcb-gpt/camber-calls
source scripts/load-env.sh
./scripts/temporal_backtest_harness.sh 14 artifacts/temporal_backtest
```

