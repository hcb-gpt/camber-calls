# DATA-4 supporting artifacts: metrics + pilot hygiene (v1)

## Owner identity metrics pack

- Run (read-only via `scripts/query.sh`):
  - `scripts/query.sh --file scripts/proofs/owner_identity_metrics_pack_v1.sql`
- Before/after template:
  - Run the file once to capture **before** (copy/paste output into the ticket).
  - Run again after an ingest/backfill change for **after**; compare the two outputs.

## Speaker diarization backfill pilot

- Measure deterministic eligible size + expected resolution (read-only):
  - `scripts/query.sh --file scripts/proofs/speaker_backfill_pilot_metrics_v0.sql`
- Pilot apply / rollback (mutating; run only with explicit STRAT go/no-go):
  - Apply: `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/backfills/speaker_backfill_pilot_apply_v0.sql`
  - Rollback: `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/backfills/speaker_backfill_pilot_rollback_v0.sql`

## Deepgram transcript duplication hygiene

- Quantify null-variant dupes (read-only):
  - `scripts/query.sh --file scripts/proofs/deepgram_transcript_dup_metrics_v0.sql`
- Cleanup script (mutating; run only with explicit STRAT go/no-go):
  - `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f scripts/backfills/deepgram_transcripts_dedupe_v0.sql`

