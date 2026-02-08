# CAMBER Calls

Supabase Edge Functions and scripts for CAMBER call ingestion, segmentation,
attribution, and replay tooling.

## Core Functions

- `process-call`: ingress pipeline, idempotency, persistence, and orchestration.
- `segment-call`: span producer + per-span context/attribution chaining.
- `segment-llm`: transcript segmentation with staged OpenAI/Anthropic cascade
  and deterministic fallback split.
- `context-assembly`: candidate building and evidence packaging.
- `ai-router`: staged OpenAI/Anthropic attribution cascade with conservative
  disagreement handling.
- `admin-reseed`: replay/resegment utilities for correction and backfill
  workflows.

## Cascade Configuration

The following env vars control staged dual-provider cascade behavior:

- `SEGMENT_LLM_OPENAI_MODELS` (comma-separated)
- `SEGMENT_LLM_ANTHROPIC_MODELS` (comma-separated)
- `AI_ROUTER_OPENAI_MODELS` (comma-separated)
- `AI_ROUTER_ANTHROPIC_MODELS` (comma-separated)
- `CASCADE_STAGE_TIMEOUT_MS` (per-stage timeout)
- `CASCADE_MAX_STAGES` (caps ladder depth)
- `CASCADE_BOUNDARY_TOLERANCE_CHARS` (segment boundary agreement window)

If a provider model is unavailable (permission/404/etc), cascade skips it and
continues.

## Local Development

```bash
# Install Supabase CLI
brew install supabase/tap/supabase

# Link project (if needed)
supabase link --project-ref rjhdwidddtfetbwqolof

# Serve selected functions locally
supabase functions serve segment-llm --env-file .env.local
supabase functions serve ai-router --env-file .env.local
```

## Smoke Validation

Run the push-button cascade smoke script:

```bash
source ./scripts/load-env.sh
./scripts/smoke_cascade.sh
```

What it checks:

- `segment-llm` returns `ok=true` with multi-segment-capable output/warnings.
- `ai-router` returns `ok=true` in `dry_run=true` mode with cascade metadata.
- No DB writes from router smoke path.

Optional override:

- `SUPABASE_FUNCTIONS_BASE_URL` to target local or alternate function base URL.
- `CASCADE_TRANSCRIPT_FILE` to supply a custom transcript fixture.

## CI/CD

Pushes to `main` deploy via GitHub Actions.

Required secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_ID` (`rjhdwidddtfetbwqolof`)
