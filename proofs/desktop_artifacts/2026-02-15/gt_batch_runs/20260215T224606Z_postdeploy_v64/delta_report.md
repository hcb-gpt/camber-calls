# GT Smoke Delta Report (Post-Deploy ai-router v64)

## Scope
- Baseline reference (pre-deploy): `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z`
- Post-deploy run: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64`
- Deploy proof reference: `completion__dev2__merge_deploy_homeowner_override_gate_v1__20260215` (ai-router v64 active at 2026-02-15T22:43:00Z)

## Headline Delta (Baseline -> Post-Deploy)
- Accuracy: `0.40 -> 0.30` (`-0.10`)
- Review rate: `0.70 -> 0.5556` (`-0.1444`)
- Homeowner override fail count: `0 -> 0` (`+0`)
- Staff leak count: `0 -> 0` (`+0`)
- Trigger fail count: `0 -> 0` (`+0`)

## Homeowner-Tagged / Winship-Related Outcomes (Post-Deploy)
- `smoke_08` (`cll_06DFWX6DQNYKF4QE46STT6BHZW`): expected project `159ae416-b397-48a0-97dd-cf1249119715`, actual project `Winship Residence`, decision `review`.
- `smoke_09` (`cll_06DFWYKYQSW9XASM4M16CAJC80`): expected project `310a3768-d7c0-4e72-88d0-aa67bf4d1b05`, actual project `Winship Residence`, decision `assign`.
- `smoke_10` (`cll_06DFWYV90DSTZ6351E3CEPHQ70`): expected project `159ae416-b397-48a0-97dd-cf1249119715`, actual project `Winship Residence`, decision `review`.

## Evidence Files
- Metrics: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64/metrics.json`
- Results: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64/results.csv`
- Failures: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64/failures.csv`
- Trigger outcomes: `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T224606Z_postdeploy_v64/trigger_results.csv`

## Note on Baseline Artifact Availability
The baseline folder `/Users/chadbarlow/Desktop/gt_batch_runs/20260215T221308Z` is no longer present on local disk, so this delta uses baseline headline metrics previously recorded in `completion__dev1__gt_regression_batch_runner_v1__20260215`.
