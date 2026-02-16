# World Model Seed Tool (`jsonl -> sql`)

This tool converts JSONL world-model facts into a seed SQL file that DATA can run with `psql`.

Output SQL behavior:
- Creates `public.evidence_events` rows for manual provenance (one per unique `project_id + source_batch_id`) when `evidence_event_id` is not provided.
- Inserts `public.project_facts` rows referencing `evidence_event_id`.
- Uses deterministic `source_id` for manual evidence + `ON CONFLICT DO NOTHING`.
- Uses `WHERE NOT EXISTS` on fact inserts to avoid straightforward duplicate re-inserts.

## Run

```bash
deno run --allow-read --allow-write scripts/world_model/seed_jsonl_to_sql.ts \
  --input scripts/world_model/examples/sample_facts.jsonl \
  --output scripts/world_model/examples/sample_seed.sql \
  --summary-out scripts/world_model/examples/sample_summary.txt \
  --generated-at 2026-02-16T00:00:00Z
```

## Input JSONL schema (strict)

Required keys per line:
- `project_id` (uuid)
- `as_of_at` (ISO8601)
- `observed_at` (ISO8601)
- `fact_kind` (text)
- `fact_payload` (non-null JSON)

Optional keys per line:
- `evidence_event_id` (uuid)
- `interaction_id` (text)
- `source_span_id` (uuid)
- `source_char_start` (int, with `source_char_end`)
- `source_char_end` (int, with `source_char_start`, must be greater)
- `source_batch_id` (text)
- `source_run_id` (text)
- `source_metadata` (JSON object)

Row requirement:
- Each row must provide either `evidence_event_id` or `source_batch_id`.
- You can provide `--default-source-batch-id` as a fallback for rows missing `source_batch_id`.

Strict validation:
- Unknown keys are rejected.
- Malformed UUIDs/timestamps are rejected.
- Invalid span offset combinations are rejected.

## Deterministic examples

Included examples:
- Input: `scripts/world_model/examples/sample_facts.jsonl`
- Output SQL: `scripts/world_model/examples/sample_seed.sql`
- Summary: `scripts/world_model/examples/sample_summary.txt`

With fixed `--generated-at`, repeated runs produce byte-identical SQL/summary outputs.

## Notes

- The generated SQL mutates data when executed.
- Execute intentionally via `psql` (not `scripts/query.sh`).
- The tool does not perform database writes directly.
