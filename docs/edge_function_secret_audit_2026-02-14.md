# Edge Function Secret Audit (2026-02-14)

- Timestamp (UTC): `2026-02-14T16:17:21Z`
- Project: `rjhdwidddtfetbwqolof` (dd619142 / gandalf)
- Scope: all deployed Edge Functions from `supabase functions list` (23 total)

## Method

1. Pulled deployed function inventory and `verify_jwt` flags via:
   - `supabase functions list --project-ref rjhdwidddtfetbwqolof --output json`
2. Pulled live secret inventory via:
   - `supabase secrets list --project-ref rjhdwidddtfetbwqolof --output json`
3. Downloaded all deployed function sources to `/tmp/supa_fn_audit` and scanned `index.ts` for:
   - auth headers (`X-Edge-Secret`, `X-Secret`, `Authorization`)
   - required env vars (`Deno.env.get(...)`)
4. Ran live auth probes for high-risk mismatches.

## Live Secret Inventory (Auth-Relevant)

- Present: `EDGE_SHARED_SECRET`, `ALLOWED_EMAILS`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`
- Present (legacy transitional): `ZAPIER_INGEST_SECRET`, `ZAPIER_SECRET`

## Findings

### 1) Reliability Mismatch: `journal-extract` auth path conflicts with deploy config

- Deployed config: `verify_jwt=true`
- Runtime code path includes `X-Edge-Secret` machine auth.
- Pipeline caller (`segment-call`) invokes `journal-extract` with `X-Edge-Secret` only.
- Live probe result:
  - `POST /functions/v1/journal-extract` with valid `X-Edge-Secret` returned `401 {"message":"Missing authorization header"}`.

Impact:
- Post-attribution `journal-extract` hook from `segment-call` is likely failing at gateway auth.

Recommended fix:
- Either set `journal-extract` to `verify_jwt=false` (canonical machine-to-machine pattern), or
- change caller to include bearer JWT expected by gateway.

### 2) Security Gap: `ai-router` is publicly callable (no auth gate)

- Deployed config: `verify_jwt=false`
- Runtime code has no incoming auth gate (`X-Edge-Secret` / JWT validation absent).
- Live probe:
  - unauthenticated `POST /functions/v1/ai-router` returned `400 missing_context_package` (not `401 unauthorized`).

Impact:
- Endpoint is reachable without auth and can be abused for arbitrary invocation attempts.

Recommended fix:
- Add canonical `X-Edge-Secret` gate (matching `process-call` / `segment-call` pattern).

### 3) Missing Secrets for `sync-google-contacts`

- Required in function code: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`.
- Not present in current secret store.

Impact:
- Function will fail if invoked in production.

Recommended fix:
- Set missing Google OAuth secrets or disable/deprecate function until configured.

## Pass Checks

- `EDGE_SHARED_SECRET` is present and consistent for machine-auth functions.
- `ZAPIER_INGEST_SECRET` + `ZAPIER_SECRET` are present (matching digests), restoring transitional legacy path.
- `ALLOWED_EMAILS` is present for JWT allowlist paths.

## Notes on Optional Missing Env Vars

These are absent but have safe code defaults and are not blockers:
- `GENERATE_SUMMARY_MODEL`
- `JOURNAL_CONSOLIDATE_MODEL`
- `JOURNAL_CONSOLIDATE_TIMEOUT_MS`
- `JOURNAL_EXTRACT_TIMEOUT_MS`
