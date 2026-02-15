# SQL Proofs Pack (time-sync / project_facts)

Read-only query helpers for verifying time-sync invariants and provenance hygiene.

## Usage

- Prereq: credentials + `DATABASE_URL` available via `scripts/load-env.sh`.
- Run via the read-only wrapper:
  - `scripts/query.sh --file scripts/sql/proofs/<file>.sql`

## Proofs

- `project_facts_missing_provenance.sql`
  - Finds facts with inconsistent/missing span pointer fields.
- `project_facts_now_leakage_template.sql`
  - Template to check AS_OF vs POST_HOC (requires setting the `interaction_id` literal).
- `project_facts_window_counts.sql`
  - Quick counts of facts inside/outside a default 90d window (requires setting the `interaction_id` literal).

