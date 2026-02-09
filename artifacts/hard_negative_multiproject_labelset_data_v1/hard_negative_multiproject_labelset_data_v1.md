# hard_negative_multiproject_labelset_data_v1

Generated UTC: 2026-02-08T22:02:35.348994Z
Time split cutoff UTC: 2026-01-29T19:10:01Z

## Deliverables
- JSON: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/hard_negative_multiproject_labelset_data_v1/hard_negative_multiproject_labelset_data_v1.json
- CSV: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/hard_negative_multiproject_labelset_data_v1/hard_negative_multiproject_labelset_data_v1.csv

## Schema
- anchor_interaction_id, contact_id, contact_name, event_at_utc
- split(train|holdout), label(positive|hard_negative)
- project_id(anchor), candidate_project_id(candidate)
- difficulty_tier(positive|easy|medium|hard), time_delta_days, rationale_label

## Construction Rules
1) Scope contacts with >=2 distinct projects in interactions
2) Positive rows: observed project on each anchor interaction
3) Hard negatives: other projects for same contact within +/-30 days
4) Time split: chronological 80/20 cutoff (no random split)

## Counts by split/label/difficulty
- holdout | hard_negative | easy: 28
- holdout | hard_negative | hard: 127
- holdout | hard_negative | medium: 9
- holdout | positive | positive: 34
- train | hard_negative | easy: 189
- train | hard_negative | hard: 296
- train | hard_negative | medium: 111
- train | positive | positive: 210
