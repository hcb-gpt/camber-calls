# launch_overfit_control_scorecard_data_v1

Generated UTC: 2026-02-08T22:02:35.348994Z

## Go/No-Go Thresholds
- Temporal consistency >= 99.0%
- Hard-negative holdout accuracy >= 85.0%
- Open review ratio <= 10.0%
- Human correction rate <= 5.0%

## Current Baseline
- temporal_consistency_pct: 99.09
- hard_negative_accuracy_holdout_pct: not_measured
- hard_negative_labelset_holdout_rows: 164
- open_review_ratio_pct: 5.06
- human_correction_rate_pct_latest: 0.0

## Status
- temporal_consistency: PASS
- hard_negative_accuracy: BLOCK (missing eval run)
- abstention_quality: PASS
- human_correction_trend: PASS

## Gaps Blocking Coordinator-Scale Launch
- No measured model accuracy on hard-negative holdout yet.
- No abstention precision/recall curve bound to holdout set yet.
- Some immutable historical review metadata can remain semantically stale after manual canonical corrections.

## Metric-to-Source Map
- temporal_consistency -> /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/project_timeline_state_graph_data_v1/project_timeline_state_graph_data_v1.json
- hard_negative_dataset -> /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/hard_negative_multiproject_labelset_data_v1/hard_negative_multiproject_labelset_data_v1.json
- human_correction_rate -> public.v_launch_review_correction_daily
- open_review_ratio -> public.review_queue status counts

- JSON: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/launch_overfit_control_scorecard_data_v1/launch_overfit_control_scorecard_data_v1.json
