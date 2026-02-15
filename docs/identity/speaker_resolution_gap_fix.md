# Speaker Resolution Gap Fix v1.0 (Deepgram diarization)

## 1. Problem Statement

Deepgram diarization produces generic speaker labels (e.g., `SPEAKER_0`, `SPEAKER_1`).
Our claim extraction pipeline stores these labels in `journal_claims.speaker_label`.

The existing resolver `resolve_speaker_contact(p_speaker_label, p_project_id)` is name/alias-based and
cannot resolve diarization labels, leaving `journal_claims.speaker_contact_id` NULL at high rates.

## 2. Approach

Add a call-aware resolution path for diarization labels:

1. Identify diarization speaker number from `SPEAKER_<n>`.
2. Restrict to 2-speaker calls (deterministic case).
3. Infer which diarization speaker corresponds to `owner` vs `other_party` using:
   - `calls_raw.direction` (inbound/outbound)
   - earliest speaker id from `transcripts_comparison.words` (preferred), or the first `SPEAKER_<n>:` line in `transcripts_comparison.transcript` (fallback)
4. Resolve to `contacts` via:
   - `lookup_contact_by_phone(calls_raw.owner_phone / other_party_phone)` (preferred)
   - fallback to `resolve_speaker_contact(calls_raw.owner_name / other_party_name)`

All of the above is implemented in SQL only (no edge-function code changes required) by:
- `public.resolve_speaker_contact_v2(...)`
- updating the `journal_claims` speaker-resolution trigger to call v2.

## 3. What This Delivers

- **Forward fix**: New `journal_claims` inserts/updates will populate `speaker_contact_id` for `SPEAKER_N` labels when the call is a 2-speaker Deepgram transcript and `calls_raw.direction` is present.
- **Backfill-ready**: Audit table + a backfill script you can run after CHAD gate.

## 4. Safety + Limitations

- **No direction → no guess.** If `calls_raw.direction` is missing or not in an inbound/outbound family, v2 returns no match.
- **Non-2-speaker calls are skipped.** Speaker resolution for multi-party calls needs a separate design (manual review / diarization-to-name alignment).
- **Assumption:** earliest Deepgram speaker (word-timing if available; else first transcript line) ≈ answerer for 2-party calls.
- **Owner-side resolution depends on contact hygiene.** In current production data, `calls_raw.owner_name` is frequently empty on eligible calls, so the v2 name fallback rarely fires. If `lookup_contact_by_phone(owner_phone)` fails (missing internal phones in `contacts`), owner diarization labels will remain unresolved.

## 5. Dry-Run Measurement Queries

### 5.1 How many unresolved diarization claims exist?

```sql
SELECT
  COUNT(*) AS total_claims,
  COUNT(*) FILTER (WHERE speaker_label ILIKE 'SPEAKER\\_%') AS diarized_claims,
  COUNT(*) FILTER (
    WHERE speaker_label ILIKE 'SPEAKER\\_%'
      AND speaker_contact_id IS NULL
  ) AS diarized_unresolved_claims
FROM public.journal_claims;
```

### 5.2 How many would resolve with v2 (dry run)?

```sql
WITH targets AS (
  SELECT
    jc.id AS journal_claim_row_id,
    jc.call_id,
    COALESCE(jc.claim_project_id, jc.project_id) AS project_id,
    jc.speaker_label
  FROM public.journal_claims jc
  WHERE jc.speaker_contact_id IS NULL
    AND jc.speaker_label ILIKE 'SPEAKER\\_%'
),
resolved AS (
  SELECT
    t.*,
    r.contact_id,
    r.match_type,
    r.match_quality
  FROM targets t
  LEFT JOIN LATERAL public.resolve_speaker_contact_v2(t.speaker_label, t.project_id, t.call_id) r ON true
)
SELECT
  COUNT(*) AS targets,
  COUNT(*) FILTER (WHERE contact_id IS NOT NULL) AS would_resolve,
  ROUND(100.0 * COUNT(*) FILTER (WHERE contact_id IS NOT NULL) / NULLIF(COUNT(*), 0), 1) AS would_resolve_pct,
  match_type,
  COUNT(*) FILTER (WHERE contact_id IS NOT NULL) AS resolved_by_type
FROM resolved
GROUP BY match_type
ORDER BY resolved_by_type DESC NULLS LAST;
```

## 6. Backfill (with Audit)

Backfill script is provided at `scripts/speaker_resolution_backfill_deepgram.sql`.

**Gate:** CHAD approval required before executing any write/backfill in production.
