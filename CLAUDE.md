# CLAUDE.md — CAMBER v4 Operating Manual

This is the single "boot + contract" doc for v4. If it's not here, it's not a rule.
Status codes are not proof. DB deltas are proof.

---

## NEW DEV FAST START (read this first)

### Canonical Call (everyone uses the same target)
**interaction_id:** `cll_06DSX0CVZHZK72VCVW54EH9G3C`

This is the real call we use for all proof + replay work.

### One Command to Validate Pipeline
```bash
./scripts/replay_call.sh cll_06DSX0CVZHZK72VCVW54EH9G3C --reseed --reroute
```

### Strict PASS Template (paste exactly)
```
PASS | cll_06DSX0CVZHZK72VCVW54EH9G3C | gen=<n> spans_total=<n> spans_active=<n> attributions=<n> review_queue=<n> gap=<n> reseeds=<n> | headSHA=<sha>
```

### Current Reality & Next Gate
- Proof pack is **PASS** on canonical call
- BUT chunking collapses to single span: `spans_total=1 spans_active=1` (transcript ~10k chars)
- **Next gate:** Make `spans_total > 1` without breaking PASS
- Currently warn-only, will become strict gate once fixed

### P0 Task: Fix Chunking
**Where:** `supabase/functions/segment-llm` + `supabase/functions/segment-call`

**Required behavior:**
- If `transcript_chars > 2000` AND chunker returns 1 span:
  1. Retry with stricter instruction ("must produce at least 2 chunks unless truly single-topic")
  2. If still 1: deterministic fallback split into 2-4 spans by char ranges
  3. Mark fallback in span metadata (`segment_metadata.fallback=true`)

**Testing with idempotency:** Use `admin-reseed` with reroute to generate new generation (canonical call already has attributions, so segment-call may refuse re-chunk due to `already_attributed` rule).

**Acceptance:** Canonical call PASS line shows `spans_total > 1` AND `gap=0`.

### Vocabulary Rule
- **In prose/logs/comments:** say "chunking" / "rechunk"
- **Legacy slugs remain:** `segment-call`, `segment-llm`, `segment_generation` (don't rename routes mid-sprint)

### Credential Protocol (mandatory before everything)

**First-time setup (if ~/.camber/ doesn't exist):**
```bash
# 1. Create credential store
mkdir -p ~/.camber

# 2. Copy credentials from source
# (Chad will provide credentials.env or point to source)
cp /path/to/credentials.env ~/.camber/credentials.env
chmod 600 ~/.camber/credentials.env

# 3. Install auto-loader in shell profile
cat >> ~/.zshrc << 'EOF'
# CAMBER Auto-load credentials
if [ -f "$HOME/.camber/load-credentials.sh" ]; then
    source "$HOME/.camber/load-credentials.sh"
fi
EOF

# 4. Copy loader script to ~/.camber/
cp scripts/load-credentials.sh ~/.camber/
chmod +x ~/.camber/load-credentials.sh

# 5. Reload shell
source ~/.zshrc
```

**Verify credentials work:**
```bash
./scripts/test-credentials.sh
# Expected: ✅ All credentials loaded
```

All scripts MUST source: `scripts/load-env.sh` (CI enforced).

### Branch Protocol (prevent drift)
**DO NOT create a branch immediately.** Start on master.

**Workflow:**
1. Stay on master
2. Read CLAUDE.md (this file)
3. Understand your task from STRAT or Phase roadmap
4. THEN create branch with meaningful name

**Branch naming:**
- Format: `<type>/<description>`
- Types: `feat/`, `fix/`, `docs/`, `test/`, `refactor/`
- Description: what you're actually doing (not random names)
- Examples:
  - `feat/chunking-retry-fallback` (Phase 1 P0)
  - `fix/segment-llm-boundary-clamp`
  - `feat/review-resolve-endpoints` (Phase 3)
  - NOT: `my-branch`, `test123`, `dev-work`

**Create branch only when ready:**
```bash
# After you know what you're doing:
git checkout -b feat/chunking-retry-fallback
```

**Why:** Random branches = documentation drift. Named branches = reviewable intent.

---

## Environment Stamp (required on every substantive edit)

Repo:
- org/repo: hcb-gpt/beside-v3.8
- branch: master
- HEAD (sha + subject): 4811106 Merge pull request #18 from hcb-gpt/merge-all-branches-to-master
Supabase:
- project ref: rjhdwidddtfetbwqolof
- functions deployed (names only): process-call, segment-call, segment-llm, context-assembly, ai-router, admin-reseed, eval-ai-router, transcribe-deepgram, transcribe-assemblyai, transcribe-claude, transcribe-whisper, transcribe-audio, review-resolve, sync-google-contacts, test-tma-fetch, dlq-enqueue
Stamp Date (UTC): 2026-01-31T19:57Z

---

## A) Mission and stoplines

### Mission (one sentence)
v4 adds LLM-powered segmentation so that a multi-project call produces **N spans → N attributions** (or fails closed), instead of forcing one project per call.

### Stoplines (never break)
1) SSOT for routing output is `span_attributions` (the row). `interactions.project_id` is not AI truth and must not be written by AI.
2) Truth promotion is monotonic: human overrides AI; AI must never override human; null never overwrites non-null.
3) Fail closed on required writes: if a required DB write fails, return **500** + `error_code`. No silent “200 OK.”

---

## B) Roles and division of labor (lane rules)

STRAT routes work and defines the acceptance tests. STRAT does **not** code, test, deploy, or rotate secrets.

DEV is paramount in execution:
- applies patches (from GPT-DEV PRs),
- runs tests,
- deploys,
- rotates secrets,
- posts receipts.

GPT-DEV-* write code only:
- diffs + PR descriptions + test steps + rollback notes,
- no deploys.

DATA-1 owns DB:
- migrations/constraints/indexes/views/RPCs,
- post-deploy measurement.

CAMBER-1 is review + block:
- can BLOCK merges/deploys on stopline violations.

Chad is referee only:
- resolves tradeoffs and conflicts, no execution tasks.

---

## C) TRAM + async comms protocol (enforced)

TRAM path (messages + downloads):
`/Users/chadbarlow/Library/CloudStorage/GoogleDrive-admin@heartwoodcustombuilders.com/My Drive/_camber/Camber/01_TRAM/`

TRAM message filename format:
`{TO}_{FROM}_{YYYYMMDDTHHMM}Z_{SUBJECT}.md`

Rules:
- First token (TO) is the recipient so Chad can route without opening.
- ≤50 words narration (code blocks don’t count).
- Use tags:
  - `⚡ CHAD:` needs a human decision
  - `🚫 BLOCKED:` cannot proceed
  - `✅ DONE:` task complete

BLOCKED protocol:
1) what is blocked
2) why
3) what decision/info unblocks
4) who can unblock
No guesswork and no workarounds.

---

## D) Message headers + receipts (mechanically verifiable)

Every message begins with:
`TO:<role/team> FROM:<role> TURN:<n> TS_UTC:<YYYY-MM-DDTHH:MMZ> RECEIPT:<artifact>`

Allowed RECEIPT formats (choose one primary):
- `PR#<n>/headSHA:<sha>/CI:<pass|fail>`
- `commit:<sha>`
- `deploy:<slug>/<sha>`
- `sql:<migration|view|fn>/<name>`
- `metric:<name>=<value>`

Valid review targeting:
- Review is valid only for the PR **headSHA** at review time.
- If headSHA changes, review is void.

“Stamp” requirement for ready/review/merge:
- PR#, baseRef, headRef, headSHA
- CI proof (link or checks output)
- diff source (PR diff output)

---

## E) Credential management (established 2026-01-31)

**Central credential store:** `~/.camber/credentials.env` (chmod 600)

All credentials auto-load in new shells via `~/.zshrc`. Scripts should source:
```bash
source "$(git rev-parse --show-toplevel)/scripts/load-env.sh"
```

Available credentials:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- EDGE_SHARED_SECRET
- ANTHROPIC_API_KEY
- OPENAI_API_KEY
- DEEPGRAM_API_KEY
- ASSEMBLYAI_API_KEY
- PIPEDREAM_API_KEY
- CLI (Supabase access token)

**Never commit credentials to git.** All `.env.local` files are gitignored.

Documentation: `~/.camber/README.md` and `CREDENTIALS.md` in repo.

---

## F) Anti-drift protocol (v2)

Drift = prod (runtime) differs from git (reviewable truth).

### Closing edge-function drift (REQUIRED)
Drift is closed only when BOTH are true:
1) Function source exists in git on main at `supabase/functions/<slug>/...`
2) Deploy is traceable to a git commit on main via receipt: `deploy:<slug>/<sha>`

No dashboard edits rule:
- Do not edit function code in Supabase Dashboard.
- If an emergency dashboard edit happens anyway, within 24 hours:
  - export/download the function source,
  - commit it to git,
  - open PR with stamp,
  - merge + redeploy from git,
  - post `deploy:<slug>/<sha>` receipt.
If not closed in 24h: feature freeze until closed (unless Chad waives explicitly).

### Closing migration drift (REQUIRED)
Drift is closed only when BOTH are true:
1) remote migration history is aligned (apply/repair)
2) migration files exist in git on main (PR merged)

---

## G) v4 Sprint 0 deliverable — LLM segmenter

### Problem statement
Current segmenting is trivial (1 call = 1 span). Multi-project calls get forced into one attribution. v4 fixes that by segmenting into multiple spans before routing.

### New component: `segment-llm`
Canonical slug: `segment-llm`
Called from: `segment-call`

Auth (internal pattern):
- `verify_jwt=false`
- Requires `X-Edge-Secret == EDGE_SHARED_SECRET`
- Requires provenance `source` in allowlist (minimum: `segment-call`, `edge`, `test`)
Optional debug auth (only if needed): verified JWT via `auth.getUser()` + allowlist.
Explicitly banned: decoding JWT payload and trusting it without verification.

Input:
```json
{
  "interaction_id": "cll_...",
  "transcript": "optional; if missing, segment-llm may fetch from calls_raw",
  "source": "segment-call",
  "max_segments": 10,
  "min_segment_chars": 200
}
```

Output (JSON only):
```json
{
  "ok": true,
  "segmenter_version": "segment-llm_v1.0.0",
  "segments": [
    {
      "span_index": 0,
      "char_start": 0,
      "char_end": 2847,
      "boundary_reason": "topic_shift",
      "confidence": 0.85,
      "boundary_quote": "…now about the Hurley job…"
    }
  ],
  "warnings": []
}
```

Guardrails:
- Clamp boundaries into [0, len(transcript)]
- Segments must be increasing, non-overlapping, and contiguous (cover full transcript)
- Enforce `min_segment_chars` by merging undersized segments into previous
- Enforce `max_segments` by merging low-confidence boundaries

Fallback:
- If the LLM fails or output is invalid, return one full-call segment with `warnings=["llm_failed_fallback"]`.

Segmenter never does:
- never assigns project truth
- never writes DB
- never drops transcript content

---

## H) Orchestration (call → N spans → N attributions)

Chain:
`process-call → segment-call → segment-llm → (for each span) context-assembly → ai-router`

`segment-call` responsibilities (v4):
1) Fetch transcript (from request or calls_raw)
2) Call `segment-llm` to get boundaries
3) Upsert N rows into `conversation_spans` (span_index 0..N-1, char offsets, transcript_segment substring, word_count, segmenter_version, segment_reason, optional metadata)
4) For each span: call `context-assembly`, then `ai-router` (forward `dry_run`)

Idempotency:
- Span key is `(interaction_id, span_index)`
- Reseed rule (Sprint 0):
  - If any `span_attributions` exist for the interaction’s spans: do NOT re-segment. Return **409** with `error_code="already_attributed"` (or no-op with warning). No destructive reseeding without explicit CAMBER-1 approval.

DB note:
- Storing boundary confidence/quote cleanly is easier with `conversation_spans.segment_metadata jsonb`. If missing, add a migration (DATA-1).

---

## I) Attribution uniqueness decision gate (DATA-A + DATA-1)

We must choose and enforce ONE meaning:

Option A — canonical per span (simple):
- enforce `UNIQUE(span_id)` for `span_attributions`
- router upserts on `span_id`
- pro: one truth row
- con: loses prediction history

Option B — history per (model,prompt) (forensics/eval):
- enforce `UNIQUE(span_id, model_id, prompt_version)`
- router upserts on that composite
- pro: preserves evolution
- con: downstream must query “current” by prompt/version or latest timestamp

Until decided: do not change constraints silently; document which option is active in the Environment Stamp.

---

## J) Acceptance tests (DEV executes)

Synthetic multi-project (forced switch):
- Use a transcript with an explicit switch (“Now about Hurley… also Skelton…”)
- Expected: `conversation_spans` count >= 2 and offsets valid

Write-run proof (dry_run=false):
- Expected: span count = attribution row count for that interaction
- If any required write fails: HTTP 500 + `error_code`

Single proof query (standard):
```sql
SELECT
  cs.span_index,
  cs.id AS span_id,
  sa.decision,
  sa.project_id,
  sa.applied_project_id,
  sa.confidence,
  sa.attribution_lock,
  sa.model_id,
  sa.prompt_version,
  sa.attributed_at
FROM conversation_spans cs
LEFT JOIN span_attributions sa ON sa.span_id = cs.id
WHERE cs.interaction_id = '<interaction_id>'
ORDER BY cs.span_index;
```

Success criteria:
- `span_index` is 0..N-1 with no gaps
- attribution rows present for each span (or chain failed closed)
- decision in ('assign','review','none')

Protocol marker:
- You may write **CHAIN WRITE VERIFIED** only after the query above shows N spans and N attribution rows (or after a fail-closed 500 is observed with logged `error_code`).

---

## K) Phased Roadmap (STRAT TURN 79)

### Phase 1: Fix Chunking Quality
**Gate:** Canonical call shows `spans_total > 1` AND PASS

**DEV tasks:**
1. Make single-span on long transcripts self-correcting
   - If `transcript_chars > 2000` AND chunker returns 1 span: retry with stricter instruction, then fallback to deterministic split
   - Mark fallback in metadata
2. Upgrade warning to controlled gate (after fix ships)
   - Canonical call requires `spans_total > 1`
   - Keep warn-only for other calls initially
3. Re-run proof-pack with strict template

**DATA-1 tasks:**
1. Add `transcript_chars` to scoreboard output
2. Add chunk quality distribution query (% calls where `transcript_chars > 2000` and `spans_total = 1`)

**CAMBER-1 review:**
- Verify no correctness regression: fallback chunking preserves idempotency, no partial writes, SSOT unchanged
- If proof-pack PASS and no new gaps: approve fast

**GPT-DEV tasks:**
- GPT-DEV-1: Add `--strict-chunking` mode to replay script
- GPT-DEV-2: Update proof SQL with `expected_min_spans` + FAIL_REASON rows
- GPT-DEV-3: Draft chunker prompt upgrade for more splits on long calls

### Phase 2: Backfill + Batch Replay + Ops Signals
**Gate:** `gap_count = 0` AND CI stays green

**DEV tasks:**
1. Run `scripts/shadow_batch_autopick.sh` nightly
2. Make failures actionable (retry list + DLQ list output)

**DATA-1 tasks:**
1. Make `scripts/regression_detector_v2.sql` daily check
2. Add snapshot retention/pruning

**GPT-DEV tasks:**
- GPT-DEV-4: Extend autopick to include chunk quality failures
- GPT-DEV-6: Turn daily digest into scheduled runner (CI cron)

### Phase 3: Review Workbench Backend
**Gate:** "resolve" action is idempotent + audited + clears queues

**DEV tasks:**
1. Implement minimal backend endpoints/RPCs:
   - List open review items
   - Resolve item (approve/change/unknown) with idempotency key
2. Every resolve action must:
   - Write/append span_attributions
   - Append override_log receipt
   - Update review_queue status
3. Add smoke script: create dummy review item → resolve → proof query PASS

**GPT-DEV tasks:**
- GPT-DEV-5: Provide exact DB write pseudocode for review resolve + idempotency model + smoke-test

### Phase 4: Resolution Layer + Eval Loop
**Gate:** Proposal→confirm pipeline works on sampled calls

**DEV tasks:**
1. Add proposal tables for project/contact mapping from span_attributions receipts
2. Add human confirm action (append-only mappings)
3. Start eval runs: sample N calls/week, score from receipts, flag K items for spot-check

**GPT-DEV tasks:**
- GPT-DEV-7: Draft schema + flow for proposals → confirm → append-only mapping + "current mapping" views
- GPT-DEV-8: Draft alias rollout plan (introduce `chunk-*` aliases without breaking callers)

