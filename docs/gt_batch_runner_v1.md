# GT Batch Runner v1

`gt_batch_runner` runs a regression batch, optionally triggers pipeline execution, and writes deterministic artifacts to Desktop.

## Input Format (`gt_batch_v1.csv` or `.json`)

Required column/field:
- `interaction_id`

Optional:
- `row_id`
- `span_index` (defaults to `0`)
- `span_id` (overrides `span_index` when provided)
- `expected_project_id`
- `expected_project_name_contains`
- `expected_decision` (`assign|review|none`)
- `notes`
- `tags`

CSV header example:

```csv
row_id,interaction_id,span_index,span_id,expected_project_id,expected_project_name_contains,expected_decision,notes,tags
smoke_01,cll_...,0,,310a...,Winship,assign,homeowner check,homeowner_override
```

JSON example:

```json
[
  {
    "row_id": "smoke_01",
    "interaction_id": "cll_...",
    "span_index": "0",
    "expected_project_name_contains": "Winship",
    "expected_decision": "assign",
    "tags": "homeowner_override"
  }
]
```

## One-Command Smoke Run

```bash
scripts/gt_batch_runner.sh \
  --input tests/fixtures/gt_batch_v1_smoke.csv \
  --mode shadow
```

## Modes

- `--mode shadow` (default): calls `shadow-replay` per interaction and evaluates shadow interaction output.
- `--mode reseed`: calls `admin-reseed` per interaction (`--reseed-mode resegment_and_reroute|reseed_and_close_loop`).
- `--mode none`: no trigger; evaluate current DB state only.

## Output

Each run writes to:

- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/summary.md`
- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/results.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/failures.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/metrics.json`
- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/trigger_results.csv`
- `/Users/chadbarlow/Desktop/gt_batch_runs/<timestamp>/diff.json` (when baseline available)

Reported metrics include:
- `accuracy`
- `review_rate`
- `homeowner_override_fail_count`
- `staff_leak_count`
- `multi_project_span_count`
- `missing_char_offsets_count`

## Diff Mode

Compare against a baseline run:

```bash
scripts/gt_batch_runner.sh \
  --input tests/fixtures/gt_batch_v1_smoke.csv \
  --mode none \
  --baseline /Users/chadbarlow/Desktop/gt_batch_runs/<baseline_ts>
```
