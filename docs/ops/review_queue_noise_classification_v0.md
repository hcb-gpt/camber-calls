# Review queue noise classification (v0)

This pack targets **interaction-level** review items (pending rows with `span_id IS NULL`).

## Read-only proof

- Run:
  - `scripts/query.sh --file scripts/proofs/review_queue_noise_classification_v0.sql`

Outputs:
- pending NULL-span counts (overall + module split)
- bucketed classification: `synthetic_test` vs `stale_already_resolved` vs `missing_interaction_row` vs `real_pending`
- reason code distribution + a sample of newest `real_pending` rows for inspection

## Cleanup recommendation (gated)

The minimal “safe” cleanup is to only touch **pending** NULL-span rows:

- **Dismiss** synthetic/test rows:
  - `calls_raw.is_shadow = true` OR `calls_raw.test_batch is not null` OR signal raw_event test_batch present
- **Resolve** stale rows where the interaction is already resolved:
  - `interactions.needs_review = false` OR (`interactions.contact_id` and `interactions.project_id` are both non-null)
- **Dismiss** rows missing an `interactions` record (cannot be acted on)

Mutating script (only with explicit STRAT go/no-go):
- `psql \"$DATABASE_URL\" -v ON_ERROR_STOP=1 -f scripts/backfills/review_queue_noise_cleanup_v0.sql`

