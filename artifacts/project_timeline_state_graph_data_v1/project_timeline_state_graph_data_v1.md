# project_timeline_state_graph_data_v1

Generated UTC: 2026-02-08T22:02:35.348994Z

## Deliverables
- JSON: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/project_timeline_state_graph_data_v1/project_timeline_state_graph_data_v1.json
- CSV: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/project_timeline_state_graph_data_v1/project_timeline_state_graph_data_v1.csv

## Normalized Event Schema
- project_id, project_name, event_time, event_type, event_source
- interaction_id, contact_id, contact_name, owner_name, confidence, notes

## Extraction Logic
1) project_record_update events from projects.updated_at
2) interaction_touchpoint events from interactions rows with non-null project_id
3) review_resolution events from review_queue joined by interaction_id -> interactions.project_id

## Data Quality Checks
- missing_event_time_count: 7
- contradictory_timestamp_count: 0
- project_name_missing_count: 0
- orphan_review_rows_count: 349
