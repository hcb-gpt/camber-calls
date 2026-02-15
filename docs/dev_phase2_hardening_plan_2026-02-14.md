# DEV Phase 2 Hardening Plan (2026-02-14)

## Scope
Roadmap receipt: `dev_roadmap_phase2_pipeline_hardening`.
Goal: ensure all live ingest paths are deterministic, observable, and recoverable.

## Item 1: Provenance Gate Audit Sweep
Status: Completed in this cycle.

Changes applied:
- Removed provenance-source allowlist from edge-secret auth gate in:
  - `supabase/functions/process-call/index.ts`
  - `supabase/functions/generate-summary/index.ts`
  - `supabase/functions/segment-call/index.ts`
  - `supabase/functions/segment-llm/index.ts`
  - `supabase/functions/striking-detect/index.ts`
  - `supabase/functions/chain-detect/index.ts`
- Verified clean/no provenance gate needed in:
  - `supabase/functions/context-assembly/index.ts`

Gateway/JWT config hardening:
- Set `verify_jwt=false` for machine-auth functions that rely on internal `X-Edge-Secret`:
  - `striking-detect`
  - `chain-detect`
- Added function config files + root `supabase/config.toml` entries.

Validation outcome:
- Valid `X-Edge-Secret` requests with `source=openphone` no longer fail auth.
- Endpoints now return payload-validation responses (400/200) instead of provenance-based 401.

## Item 2: Diagnostic Logging Standardization
Status: Planned (next deploy cycle).

Target functions:
- `generate-summary`
- `segment-call`
- `ai-router`
- `journal-extract`

Standard write contract:
- Table: `diagnostic_logs`
- Required fields:
  - `function_name`
  - `function_version`
  - `log_level`
  - `message`
  - `metadata` (jsonb)

Event taxonomy (initial):
- `AUTH_FAILED`
- `INPUT_INVALID`
- `DOWNSTREAM_CALL_FAILED`
- `MODEL_PARSE_ERROR`
- `DB_WRITE_FAILED`
- `PIPELINE_RETRY`

Implementation shape:
- Add small local helper per function (`logDiagnostic(message, metadata, level='error')`).
- Emit at auth failures and at each non-2xx downstream boundary.
- Keep volume bounded by logging only failure and retry paths.

## Item 3: Pipeline Version Contract
Status: Planned (after Item 2).

Target stamps:
- `conversation_spans` (segment-call output)
  - already has `segmenter_version`; normalize to include function version in metadata block.
- `span_attributions` (ai-router output)
  - ensure router function version is persisted in stable field (not only model id).
- `interactions` (generate-summary output)
  - persist summary function/prompt/model version in a summary metadata object.
- `journal_claims` (journal-extract output)
  - persist extractor function version and prompt/model version.

Contract requirement:
- Every write path should expose `function_version` + `model/prompt` version where applicable.
- Enables backfill scoping and regression forensics by producer version.

## Item 4: Retry + Dead-Letter Design (Design Only)
Status: Designed; no implementation in this cycle.

### Proposed table: `pipeline_failures`
Columns:
- `id uuid primary key default gen_random_uuid()`
- `interaction_id text not null`
- `span_id uuid null`
- `failing_function text not null`
- `caller_function text null`
- `http_status int null`
- `error_code text null`
- `error_message text null`
- `attempt_count int not null default 1`
- `payload_snapshot jsonb null`
- `context jsonb null`
- `failed_at timestamptz not null default now()`
- `next_retry_at timestamptz null`
- `resolved_at timestamptz null`
- `resolution_note text null`

Indexes:
- `(interaction_id, failed_at desc)`
- `(failing_function, failed_at desc)`
- partial `(resolved_at) where resolved_at is null`

### Capture points
- `process-call -> segment-call` fire-and-forget failures
- `segment-call` post-hooks (`striking-detect`, `journal-extract`, `generate-summary`) failures
- `admin-reseed` reroute/post-hook failures

### Retry policy (initial)
- Inline retries: preserve current local single retry where already implemented.
- DLQ replay worker (future): poll unresolved rows by `next_retry_at`, retry with bounded attempts + backoff.
- Resolution path: mark `resolved_at` when replay succeeds.

### Guardrails
- Never drop failure events silently.
- Payload snapshots must redact secrets.
- DLQ writes must be best-effort but non-blocking for primary response path.

## Execution Order (next actions)
1. Implement Item 2 diagnostics in one deploy wave.
2. Implement Item 3 version stamp contract in one deploy wave.
3. Submit SQL + function-level change set for Item 4 to STRAT before coding.
