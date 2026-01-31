# Internal Function Threat Model

**Last Updated:** 2026-01-31
**Applies to:** Supabase Edge Functions with `verify_jwt=false`

## Overview

Several edge functions are configured with `verify_jwt=false` because they're called internally (function-to-function) rather than by end users. This document describes:
1. Which functions have this configuration
2. What auth mechanisms protect them
3. What prevents public invocation
4. Attack surface and mitigations

## Functions with verify_jwt=false

| Function | Purpose | Called By |
|----------|---------|-----------|
| `segment-llm` | LLM-powered transcript segmentation | `segment-call`, `admin-reseed` |
| `admin-reseed` | Re-chunk and reroute interactions | `system` (admin scripts) |
| `segment-call` | Orchestrate segmentation pipeline | `process-call` |
| `context-assembly` | Build context package for router | `segment-call`, `admin-reseed` |
| `ai-router` | Route spans to projects | `segment-call`, `admin-reseed` |
| `process-call` | Entry point for call processing | Pipedream webhook |

## Auth Stack (Defense in Depth)

### Layer 1: Gateway Auth (Required)
Even with `verify_jwt=false`, external callers MUST provide:
```
Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
```

The Supabase gateway validates this header before forwarding to functions. Requests without it receive `401 Unauthorized`.

### Layer 2: Function Auth (X-Edge-Secret)
All internal functions validate:
```
X-Edge-Secret: <EDGE_SHARED_SECRET>
```

This is checked by `requireEdgeSecret()` from `_shared/auth.ts`:
- Returns `401` if header missing
- Returns `401` if value doesn't match `EDGE_SHARED_SECRET` env var

### Layer 3: Provenance Allowlist
Each function maintains an allowlist of valid callers:
```typescript
// Example from segment-llm
const ALLOWED_PROVENANCE_SOURCES = ["segment-call", "admin-reseed", "edge", "test"];
```

Requests must include `source` in the body (or `X-Source` header) matching this list.

## What Prevents Public Invocation

1. **No public routes** - These functions aren't exposed via any public API or frontend
2. **Service role key required** - Only held by:
   - Backend services (Pipedream)
   - Admin scripts (credentials stored in `~/.camber/credentials.env`)
   - CI/CD (GitHub secrets)
3. **Edge secret required** - Second factor prevents leaked service role key alone from enabling access
4. **Source validation** - Even with both keys, requests must come from known callers

## Attack Scenarios

### Scenario 1: Leaked Service Role Key
**Risk:** Attacker has `SUPABASE_SERVICE_ROLE_KEY`

**Mitigation:** Still need `EDGE_SHARED_SECRET` to call internal functions. Functions return `401 auth_failed`.

### Scenario 2: Leaked Edge Secret
**Risk:** Attacker has `EDGE_SHARED_SECRET`

**Mitigation:** Still need service role key for gateway auth. Requests fail at gateway level.

### Scenario 3: Both Keys Leaked
**Risk:** Attacker has both keys

**Impact:**
- Can trigger rechunking/rerouting of calls
- Cannot directly modify attributions (write path is append-only)
- Cannot bypass human locks
- Cannot access data outside the pipeline

**Response:** Rotate both secrets immediately.

### Scenario 4: Source Allowlist Bypass
**Risk:** Attacker tries `source: "segment-call"` with valid keys

**Impact:** This would work - source is just a string. However:
- Attacker still can't do anything destructive
- All actions are logged with receipts
- No data exfiltration path exists

## Monitoring & Audit

- All reseed operations logged to `override_log` with receipts
- Structured logs include `source`, `request_id`, `correlation_id`
- Failed auth attempts logged with `error_code: auth_failed`

## Secret Rotation

If either secret is compromised:

1. **Edge Secret:**
   ```bash
   # Generate new secret
   openssl rand -hex 32 > /tmp/new_secret
   # Update in Supabase dashboard: Settings > Edge Functions > Environment Variables
   # Update in ~/.camber/credentials.env
   # Redeploy all functions
   ```

2. **Service Role Key:**
   - Regenerate in Supabase dashboard: Settings > API > Service Role Key
   - Update in all locations (credentials, CI secrets, Pipedream)

## Negative Test

To verify auth is working, run:
```bash
# Should return 401 - missing X-Edge-Secret
curl -s -X POST "https://rjhdwidddtfetbwqolof.supabase.co/functions/v1/segment-llm" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"interaction_id": "test", "transcript": "test", "source": "test"}'
# Expected: {"ok":false,"error":"unauthorized","error_code":"auth_failed",...}

# Should return 401 - wrong source
curl -s -X POST "https://rjhdwidddtfetbwqolof.supabase.co/functions/v1/segment-llm" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "X-Edge-Secret: $EDGE_SHARED_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"interaction_id": "test", "transcript": "test", "source": "unknown_attacker"}'
# Expected: {"ok":false,"error":"unauthorized","error_code":"auth_failed",...}
```

## Conclusion

The internal function auth stack provides defense in depth:
1. Gateway requires service role key
2. Functions require edge secret
3. Functions validate source provenance

Even with all credentials, the blast radius is limited to triggering pipeline operations (no data exfil, no attribution modification, no bypass of human locks).
