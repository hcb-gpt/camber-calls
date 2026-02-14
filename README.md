# CAMBER Edge Functions

Supabase Edge Functions for the CAMBER call processing pipeline.

## Structure

```
camber-edge-functions/
├── .github/
│   └── workflows/
│       └── deploy-edge-functions.yml   # Auto-deploy on push to main
├── supabase/
│   ├── config.toml                     # Project config
│   └── functions/
│       └── process-call/
│           └── index.ts                # v3.8 call pipeline
└── README.md
```

## Functions

### process-call

Full v3.6+ call processing pipeline:
- Idempotency check
- Event audit (write-ahead)
- M1: Normalize payload
- Contact lookup (RPC)
- Project attribution
- M4: Gatekeeper
- Persist to `calls_raw`, `interactions`
- Final audit update

**Endpoint:** `https://rjhdwidddtfetbwqolof.supabase.co/functions/v1/process-call`

## Local Development

```bash
# Install Supabase CLI
brew install supabase/tap/supabase

# Link to project
supabase link --project-ref rjhdwidddtfetbwqolof

# Serve locally
supabase functions serve process-call --env-file .env.local

# Deploy manually
supabase functions deploy process-call --no-verify-jwt
```

## CI/CD

Push to `main` triggers automatic deployment via GitHub Actions.

**Required GitHub Secrets:**
- `SUPABASE_ACCESS_TOKEN` - From [Supabase Dashboard](https://supabase.com/dashboard/account/tokens)
- `SUPABASE_PROJECT_ID` - `rjhdwidddtfetbwqolof`

## Versioning

Edge function versions tracked in code comments and `router_version` field written to `idempotency_keys`.

| Version | Date | Changes |
|---------|------|---------|
| v3.8.3 | 2026-01-30 | Initial Git-tracked version |
| v3.8.2 | 2026-01-30 | Fixed interactions schema |
| v3.8.1 | 2026-01-30 | Fixed contact_id extraction |
| v3.8.0 | 2026-01-30 | Initial Edge Function port |

## Related

- **Pipeline Entry Point:** `https://rjhdwidddtfetbwqolof.supabase.co/functions/v1/process-call`
- **Supabase Project:** `rjhdwidddtfetbwqolof`
- **Replay/Shadow:** TODO — define direct Edge-native replacement workflow
