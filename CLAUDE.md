# CLAUDE.md

## Project Overview

**CAMBER Edge Functions / Beside v3.8** - A Supabase-based call processing pipeline that automatically detects and attributes phone calls to construction projects using multi-source ranking and AI-powered review.

**Current Version:** v3.8.3

## Tech Stack

- **Runtime:** Deno (Supabase Edge Functions)
- **Language:** TypeScript
- **Database:** PostgreSQL (Supabase)
- **LLM:** Claude 3 Haiku (claude-3-haiku-20240307) for span attribution
- **Transcription:** Deepgram Nova-2

## Project Structure

```
supabase/
├── functions/
│   ├── process-call/         # v3.9.0 - Call intake + 6-source candidate ranking
│   ├── context-assembly/     # v1.2.0 - Span-first context assembly for LLM
│   ├── ai-router/            # v1.5.0 - LLM-powered span attribution
│   ├── review-resolve/       # v3.0.0 - Human review resolution
│   └── transcribe-deepgram/  # v5 - Speech-to-text with vocab boost
└── migrations/               # 397+ SQL migrations
scripts/
└── shadow-batch.sh           # Test harness for replay testing
```

## Key Commands

```bash
# Serve locally
supabase functions serve process-call --env-file .env.local

# Deploy (skip JWT for public intake)
supabase functions deploy process-call --no-verify-jwt

# Format & lint
deno fmt --check supabase/functions/
deno lint supabase/functions/

# Shadow batch testing
./scripts/shadow-batch.sh cll_xyz,cll_abc
```

## Core Database Tables

| Table | Purpose |
|-------|---------|
| `calls_raw` | Raw call archive |
| `interactions` | Normalized call records |
| `conversation_spans` | Call segments (1:1 with interactions currently) |
| `span_attributions` | Per-span project attribution (SSOT) |
| `review_queue` | Pending human review items |
| `projects` | Project metadata with aliases[], address, phase |
| `contacts` | Contact directory with phone, company, role |
| `event_audit` | Pipeline execution log |

## Architecture Principles

### Span-First Architecture
- SSOT is `span_attributions`, not `interactions.project_id`
- Enables multi-project calls and segment-level accuracy

### 6-Source Candidate Ranking
1. `project_contacts` (direct assignment) - +100
2. `correspondent_project_affinity` (historical frequency)
3. `interactions` existing_project - +80/+20
4. Transcript name/alias/location scan - +40
5. `scan_transcript_for_projects` RPC (fuzzy)
6. `expand_candidates_from_mentions` RPC
7. Geo proximity (SOURCE 7, weak signal only)

### STRAT-1 Guardrails
- **Verb-driven role tagging:** destination/origin/proximity verbs
- **Lock monotonicity:** human > ai > null (never downgrade)
- **Strong anchor enforcement:** city/zip alone forces REVIEW
- **Staff name filtering:** HCB names (e.g., "Zachary Sittler") are not project evidence

### Confidence Thresholds (ai-router)
- ≥0.75 → auto-assign with `attribution_lock='ai'`
- 0.50-0.75 → send to `review_queue`
- <0.50 → no attribution

## Environment Variables

```bash
SUPABASE_URL=https://rjhdwidddtfetbwqolof.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

## CI/CD

- **Lint/Format:** `.github/workflows/deno-ci.yml` (PRs)
- **Deploy:** `.github/workflows/deploy-edge-functions.yml` (push to main)
- **Required Secrets:** `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_ID`

## Code Conventions

- Edge functions: `kebab-case` directories
- PL/pgSQL functions: `snake_case`
- Tables: `snake_case`
- Always use word-boundary matching for transcript scanning (avoid substring false positives)
- Strip speaker labels before name matching
- All intake requests get idempotency tracking via `idempotency_keys`
- Audit-first: `event_audit` initialized on entry, updated throughout

## Testing

- **Shadow batch:** Replay production calls with `cll_SHADOW_` prefix
- **Manual:** POST to edge function endpoints with sample payloads
- **No formal test suite yet** - validation via shadow testing and audit logs

## Key RPCs

- `lookup_contact_by_phone(p_phone)` - Contact resolution
- `scan_transcript_for_projects(transcript, threshold)` - Fuzzy matching
- `expand_candidates_from_mentions(transcript)` - Contact-based inference
- `resolve_review_item(...)` - Atomic human resolution

## Recent Changes

See `RELEASES.md` for detailed changelog. Latest:
- PR-12: segment-call + X-Edge-Secret auth hardening
- PR-7: Geo proximity candidates + verb-driven enroute role tagging
- PR-5: Human resolution endpoint + review queue wiring

---

# Pipeline Operations Guide

*Added 2026-01-31 after STRAT onboarding. This section documents verified behavior, not aspirations.*

## 1. What's the Chain?

The attribution pipeline is a 4-function chain. Each function writes to specific tables:

```
process-call → segment-call → context-assembly → ai-router
```

| Function | Version (deployed) | Writes To | Purpose |
|----------|-------------------|-----------|---------|
| `process-call` | v3.9.0 | `calls_raw`, `interactions`, `event_audit`, `idempotency_keys` | Intake + 6-source candidate ranking |
| `segment-call` | v1.4.0 | `conversation_spans` | Creates spans from calls, triggers downstream chain |
| `context-assembly` | v1.2.0 | `span_place_mentions` | Assembles LLM context package; writes geo mentions |
| `ai-router` | v1.1.3 | `span_attributions`, `review_queue` | LLM attribution + gatekeeper |

**context-assembly write behavior:** Upserts to `span_place_mentions` when geo places are detected. **Fails closed** — returns 500 if upsert fails (verified in code: `return new Response(..., { status: 500 })` on upsert error).

**Branch note:** `segment-call` lives on branch `pr12-harden-process-call`, not `main` or `admiring-meninsky`. Deployed prod matches v1.4.0 from that branch.

**Supabase project:** `rjhdwidddtfetbwqolof` (prod)

## 2. How Do I Prove It Works?

### The Proof Query

After running the chain, this query proves a write occurred:

```sql
SELECT
  sa.span_id,
  sa.project_id,
  sa.applied_project_id,
  sa.decision,
  sa.confidence,
  sa.attribution_lock,
  sa.model_id,
  sa.prompt_version,
  sa.attributed_at
FROM span_attributions sa
JOIN conversation_spans cs ON cs.id = sa.span_id
WHERE cs.interaction_id = '<your_interaction_id>'
ORDER BY sa.attributed_at DESC
LIMIT 1;
```

**Success criteria:**
- Row exists
- `model_id` = 'claude-3-haiku-20240307'
- `prompt_version` = 'v1.5.0'
- `decision` IN ('assign', 'review', 'none')
- `attributed_at` within expected timeframe

### Controlled Test Procedure

**Prerequisites:** segment-call v1.4.0 accepts either:
- `transcript` field directly (creates span from provided text), OR
- Just `interaction_id` (fetches transcript from `calls_raw`)

For a clean test without touching `calls_raw`, provide transcript inline:

1. **Call segment-call with inline transcript:**
```bash
curl -X POST "$SUPABASE_URL/functions/v1/segment-call" \
  -H "Content-Type: application/json" \
  -H "X-Edge-Secret: $EDGE_SHARED_SECRET" \
  -d '{
    "interaction_id": "test_chain_'$(date +%Y%m%d_%H%M%S)'",
    "transcript": "Hey this is about the Johnson Residence project on Elm Street",
    "source": "test",
    "dry_run": false
  }'
```

2. **Run proof query** with that interaction_id

3. **If row exists with valid fields:** Chain is working. You may mark: **CHAIN WRITE VERIFIED**

**Note:** segment-call creates the `conversation_spans` row, then chains to context-assembly → ai-router. All three must succeed for the proof query to return a row.

### dry_run Behavior

- `dry_run=true`: ai-router skips all DB writes, returns result only
- `dry_run=false` (default): Writes to `span_attributions` and `review_queue`
- **Always verify `dry_run` is not accidentally true** in chain callers

## 3. Where Can It Lie To Me?

### ai-router Returns 200 Even on DB Failure (CURRENT BUG)

**Confirmed behavior** (ai-router v1.1.3 deployed 2026-01-31):

```typescript
try {
  const { error: upsertErr } = await db.from("span_attributions").upsert({...});
  if (upsertErr) {
    console.error(`[ai-router] span_attributions upsert FAILED: ${upsertErr.message}`);
    // BUG: logs error but does NOT return 500
  }
} catch (dbErr: any) {
  console.error("[ai-router] span_attributions upsert exception:", dbErr.message);
  // BUG: continues to return 200
}
// ... later returns 200 regardless
```

**Status:** Bug exists in deployed v1.1.3. Not yet fixed.

**Impact:** A 200 response from ai-router does NOT prove a write occurred. The only proof is the DB query.

**Mitigation:** Always verify writes with the proof query. Don't trust HTTP status alone.

**Contrast with context-assembly:** context-assembly v1.2.0 **does** fail closed on `span_place_mentions` upsert error (returns 500). ai-router should be fixed to match.

### event_audit Can Look Healthy While Pipeline Is Broken

Two failure modes where `SELECT gate_status, COUNT(*) FROM event_audit` looks fine:

1. **Orphaned interactions:** process-call writes event_audit=PASS, but segment-call never runs (no spans created)
2. **ai-router called but upsert fails:** Logs error, returns 200, event_audit unchanged

**Better health check:**
```sql
-- Spans without attributions (stale = older than 1 hour)
SELECT COUNT(*) as orphaned_spans
FROM conversation_spans cs
LEFT JOIN span_attributions sa ON sa.span_id = cs.id
WHERE sa.id IS NULL
  AND cs.created_at > NOW() - INTERVAL '24 hours'
  AND cs.created_at < NOW() - INTERVAL '1 hour';
```

Expected healthy: 0. Any positive number = chain is broken.

## 4. What's the Schema Trap?

### span_attributions Has Conflicting Unique Constraints

**Current state:**
1. `UNIQUE(span_id, model_id, prompt_version)` — partial index, allows history per model/prompt
2. `UNIQUE(span_id, project_id)` — prevents same span+project combo

**Deployed ai-router uses:**
```typescript
onConflict: "span_id,project_id"
```

**The conflict:**
- If you rerun with a **new prompt_version** but same **project_id**: upsert matches on `(span_id, project_id)`, updates in place. History lost.
- If model predicts a **different project_id**: inserts new row. Now you have multiple attribution rows per span.

**Open decision (not yet resolved):**
- **(A) Allow history rows:** Drop `UNIQUE(span_id, project_id)`. Use `(span_id, model_id, prompt_version)` for idempotency. Query for "latest" attribution.
- **(B) One canonical row per span:** Change to `UNIQUE(span_id)` alone. Each rerun overwrites. No history.

**Current workaround:** Don't rerun ai-router on already-attributed spans unless you understand the constraint behavior.

## 5. What's the Auth Posture?

### Allowed Patterns

Edge functions accept two auth modes:

1. **X-Edge-Secret + valid provenance** (internal edge-to-edge calls):
   ```
   X-Edge-Secret: <EDGE_SHARED_SECRET>
   Body: { "source": "process-call" | "segment-call" | "context-assembly" | "test" }
   ```

2. **JWT via auth.getUser()** (external/UI calls):
   ```
   Authorization: Bearer <supabase_access_token>
   ```
   - Token is verified by calling `supabase.auth.getUser()` — this validates signature with Supabase Auth
   - User email checked against `ALLOWED_EMAILS` env var

### Banned Pattern

**NEVER decode JWT payload and trust it without verification.**

```typescript
// ❌ WRONG - trusts unverified claims
const payload = JSON.parse(atob(token.split('.')[1]));
const userId = payload.sub;  // Attacker can forge this

// ✅ CORRECT - verifies signature with Supabase Auth
const { data: { user } } = await supabase.auth.getUser();
const userId = user.id;  // Cryptographically verified
```

This is enforced in `segment-call` v1.3.0+ and `ai-router` v1.1.0+ (PR-12).

---

## Protocol Markers

These markers indicate verified system states. Only claim them after running the proof procedure.

| Marker | Meaning | How to Earn |
|--------|---------|-------------|
| **CHAIN WRITE VERIFIED** | Full chain produced a `span_attributions` row | Run controlled test, confirm proof query returns valid row |
| **HUMAN LOCK VERIFIED** | `resolve_review_item` correctly set `attribution_lock='human'` | Resolve a review item, confirm lock in DB |

---

*Last verified: 2026-01-31 by DEV (STRAT onboarding Turn 31)*
