# Camber Bootstrap - Claude Agents

**Auto-loaded at session start** for Claude Code VSCode and Claude Desktop.

This file uses **Type 1** (agent-specific setup) + **Type 2** (product context) content architecture.

---

## Agent Setup (Type 1: How THIS agent works)

@~/gh/camber-system/boot/claude-code/setup.md

---

## Product Context (Type 2: How to work on THIS product)

@OPERATING-MANUAL.md

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
   - Credentials (Keychain + fallback)
   - Tool management (~/.camber/tools/)
   - Agent boot configs (this setup.md file)
   - GitHub: `hcb-gpt/camber-system`

---

## Quick Start

### Canonical Call (use for all testing)
**Interaction ID**: `cll_06DSX0CVZHZK72VCVW54EH9G3C`

### Validate Pipeline
```bash
./scripts/replay_call.sh cll_06DSX0CVZHZK72VCVW54EH9G3C --reseed --reroute
```

### Credentials
Loaded from `~/.camber/` via shell profile (Keychain-first)

Test with:
```bash
./scripts/test-credentials.sh
```

### Tools
Located at `~/.camber/tools/` (canonical versions, never lost)

Install to current repo:
```bash
~/.camber/install-tools.sh
```

---

## Current Sprint

**Status**: v4 pipeline optimization
**Focus**: Context assembly performance improvements
**P0 Task**: Fix chunking quality (spans_total > 1)

**For complete details**: See OPERATING-MANUAL.md (imported above)

---

## Bootstrap Notes

**This file architecture**:
- ✅ Auto-loads at session start (new, resume, clear, remote)
- ✅ NOT affected by SessionStart hooks bug (GitHub Issue #10373)
- ✅ Shared between Claude Code VSCode and Claude Desktop
- ✅ Uses `@filename` imports (max 5 hops deep)

**File locations** (hierarchical precedence):
1. Managed policy: `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS)
2. Project root: `./CLAUDE.md` (this file)
3. Project config: `./.claude/CLAUDE.md`
4. Project rules: `./.claude/rules/*.md`
5. User global: `~/.claude/CLAUDE.md`
6. Local override: `./CLAUDE.local.md` (auto-gitignored)

**Built-in commands**:
- `/init` - Generate CLAUDE.md starter
- `/memory` - Edit memory files
- `/clear` - Clear conversation

---

**🚀 Bootstrap complete**. All agent setup and product context loaded.
