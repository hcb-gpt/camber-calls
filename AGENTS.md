# Camber Bootstrap - OpenAI Agents

**Agent Type**: OpenAI Codex VSCode
**Auto-loaded**: Yes (AGENTS.md auto-read at session start)
**Import syntax**: None (plain text, inline content)

---

You are working on **Camber**, an intelligence layer for Heartwood Custom Builders.

---

## Repository Architecture

**Three-repo structure**:

1. **camber/** (THIS REPO) - THE PRODUCT (what ships to production)
   - Edge functions, MCP server, packages, DB migrations
   - Product docs, dev tools (replay, migration utils)
   - GitHub: `hcb-gpt/camber`

2. **orbit/** - THE WORKSPACE (how we build)
   - TRAM message routing, ORBIT agent orchestration
   - Governance (RULE_DECK, protocols, ADRs)
   - Prompts, evals, runbooks, process tools
   - GitHub: `hcb-gpt/orbit`

3. **camber-system/** - AGENT BOOTSTRAP (how agents connect)
   - Credentials (Keychain + fallback `~/.camber/`)
   - Tool management (`~/.camber/tools/`)
   - Agent boot configs
   - GitHub: `hcb-gpt/camber-system`

---

## Canonical Call for Testing

**Interaction ID**: `cll_06DSX0CVZHZK72VCVW54EH9G3C`

**Purpose**: Standard test call for all pipeline validation and proof work

**Usage**: **Always** test pipeline changes with this call before committing

**Test command**:
```bash
./scripts/replay_call.sh cll_06DSX0CVZHZK72VCVW54EH9G3C --reseed --reroute
```

**Expected output** (PASS template):
```
PASS | cll_06DSX0CVZHZK72VCVW54EH9G3C | gen=<n> spans_total=<n> spans_active=<n> attributions=<n> review_queue=<n> gap=<n> reseeds=<n> | headSHA=<sha>
```

---

## Credentials

**Loaded from**: `~/.camber/` via shell profile (Keychain-first, fallback to `credentials.env`)

**Key environment variables**:
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (full access)
- `EDGE_SHARED_SECRET` - Edge function auth secret
- `ANTHROPIC_API_KEY` - Claude API key
- `OPENAI_API_KEY` - OpenAI API key
- `DEEPGRAM_API_KEY` - Deepgram transcription API
- `ASSEMBLYAI_API_KEY` - AssemblyAI transcription API
- `PIPEDREAM_API_KEY` - Pipedream API key

**Verify credentials work**:
```bash
./scripts/test-credentials.sh
# Expected: ✅ All credentials loaded
```

**Load credentials in scripts** (pattern):
```bash
#!/bin/bash
set -euo pipefail

# Auto-load credentials
if [[ -f "$HOME/.camber/load-credentials.sh" ]]; then
  source "$HOME/.camber/load-credentials.sh" 2>/dev/null || true
fi

# Verify loaded (fail closed)
for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing env var: $var" >&2
    exit 2
  fi
done
```

---

## Tools

**Central tool repository**: `~/.camber/tools/`

**Why**: Tools in repo `scripts/` can be lost on branch switches. Canonical versions in `~/.camber/tools/` survive all operations.

**Essential tools (5 scripts)**:
1. `replay_call.sh` (8.5K) - Pipeline validation
2. `test-credentials.sh` (1.1K) - Credential verification
3. `load-env.sh` (1.2K) - Script credential loader (sourced by all scripts)
4. `shadow-batch.sh` (3.2K) - Batch shadow testing
5. `test-shadow.sh` (891B) - Individual shadow testing

**Install tools to current repo**:
```bash
~/.camber/install-tools.sh
# ✅ All 5 tools installed to ./scripts/
```

**Check sync status**:
```bash
~/.camber/sync-tools.sh --check
# Shows: ✅ in sync / ⚠️ differs / ❌ missing
```

---

## How to Access Context

### RULE_DECK (Agent Memory)
**Location**: `~/gh/orbit/governance/rule_deck/`
**Content**: 85 rules total, organized by role
**Roles**: STRAT, DEV, DATA, KAIZEN, etc.
**Purpose**: Memory cards for agent decision-making

### TRAM Messages (Communication)
**Location**: Google Drive folder → `01_TRAM`
**Full path**: `/Users/chadbarlow/Library/CloudStorage/GoogleDrive-admin@heartwoodcustombuilders.com/My Drive/_camber/Camber/01_TRAM/`
**Protocol**: TO/FROM headers, receipts, BLOCKED signals
**Purpose**: Async message routing between agents and STRAT

### Product Documentation
**Primary**: See `OPERATING-MANUAL.md` in this repo
**Content**: Architecture, sprint status, canonical call, environment stamp, protocols
**Update frequency**: On every substantive edit

---

## Git Workflow

1. **Create feature branch from main** - Never work directly on main
   ```bash
   git checkout -b feat/description
   ```

2. **Make changes and test with replay_call.sh** - Validate before committing
   ```bash
   ./scripts/replay_call.sh cll_06DSX0CVZHZK72VCVW54EH9G3C --reseed --reroute
   ```

3. **Create PR for review** - All changes require review
   ```bash
   gh pr create --title "feat: description" --body "..."
   ```

4. **Deploy to staging before production** - Never deploy directly to production

**Branch naming convention**:
- `feat/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `test/description` - Test additions/updates
- `refactor/description` - Code refactoring

**Examples**:
- `feat/chunking-retry-fallback` (Phase 1 P0)
- `fix/segment-llm-boundary-clamp`
- `feat/review-resolve-endpoints` (Phase 3)

**NOT**: `my-branch`, `test123`, `dev-work` (random names create drift)

---

## Current Sprint

**Status**: v4 pipeline optimization
**Focus**: Context assembly performance improvements

**P0 Task**: Fix Chunking Quality
- **Problem**: Long transcripts collapse to single span (spans_total=1)
- **Required**: Make spans_total > 1 for transcripts > 2000 chars
- **Where**: `supabase/functions/segment-llm` + `supabase/functions/segment-call`
- **Acceptance**: Canonical call PASS with `spans_total > 1` AND `gap=0`

**Next gate**: Canonical call shows `spans_total > 1` without breaking PASS

---

## Team Roles

**STRAT** (your manager):
- Routes work and defines acceptance tests
- Does NOT code, test, deploy, or rotate secrets
- Gives you tasks via TRAM (check daily)

**DEV** (executor):
- Applies patches (from GPT-DEV PRs)
- Runs tests
- Deploys
- Rotates secrets
- Posts receipts back to STRAT via TRAM

**When to write TO:STRAT**:
- Task complete (with receipt: commit SHA, PR number, deploy slug)
- Blocked and need help (use BLOCKED protocol)
- Found issue requiring decision
- Daily status if working multi-day task

---

## Detailed Architecture and Operating Procedures

For complete details, read `OPERATING-MANUAL.md` in this directory.

**Key sections**:
- Mission and stoplines
- Roles and division of labor
- TRAM + async comms protocol
- Credential management
- Anti-drift protocol
- Sprint 0 deliverable (LLM segmenter)
- Orchestration (call → N spans → N attributions)
- Acceptance tests
- Phased roadmap

---

## Bootstrap Notes

**This file (AGENTS.md)**:
- ✅ Auto-read by Codex when session starts in this repo
- ✅ Applies to both new and resumed sessions
- ❌ No `@filename` import syntax (OpenAI limitation - use inline content)
- ✅ Can configure instruction filenames via `.codex/config.toml`

**File locations**:
- Project: `./AGENTS.md` (this file)
- Global: `~/.codex/AGENTS.md`
- Override: `./AGENTS.override.md` (supersedes other settings)
- Config: `~/.codex/config.toml` or `$CODEX_HOME/config.toml`

---

**🚀 Bootstrap complete**. Ready to work on Camber product.
