# Global pipeline drift metrics (v0)

Read-only health snapshot across:
- `review_queue` pending invariants (null span, superseded span, span/interaction mismatch)
- model-error review rows
- latest span attribution coverage gaps
- oversize span incidence
- review spans missing extraction (view)

Run:
- `scripts/query.sh --file scripts/proofs/global_pipeline_drift_metrics_v0.sql`

Notes:
- This is intended for “before/after” drift comparison when applying migrations, backfills, or guardrails.
- The oversize threshold is hardcoded to `> 12000` chars as a coarse regression signal.

