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
- `ci_gates_summary.sql`
  - Calls the built-in CI gates (PASS/FAIL) and returns violation counts.
- `span_attribution_coverage_last30d.sql`
  - Coverage snapshot for active spans in the last 30d: attributed vs pending-review vs uncovered.
- `span_attribution_coverage_for_interaction_template.sql`
  - Template: coverage for a single interaction_id.
- `review_queue_pending_null_span.sql`
  - Counts pending review items missing span_id, broken down by reason_codes.
- `review_queue_pending_on_superseded_span.sql`
  - Finds pending review items pointing at superseded spans (stale review rows).
- `interactions_errors_last30d.sql`
  - Pipeline error sink counts (interactions moved to `interactions_errors`) by reason for last 30d.
- `span_oversize_last30d.sql`
  - Heuristic oversize span scan for last 30d (very long transcript_segment/word_count).
- `attributions_to_closed_projects_last30d.sql`
  - Quantifies span attributions in last 30d that point to projects with `phase='closed'` (or closed-ish status) and breaks down by contact.
- `span_oversize_last30d_with_people.sql`
  - Oversize spans joined to interactions for owner/contact context (useful for GT acceptance like Randy Booth/Jimmy Chastain).
- `interaction_transcript_parent_mismatch_v1.sql`
  - Detects interactions where `transcript_chars=0` while active conversation spans contain transcript text.
