# AGENTS.md - Camber Calls (Local Agents)

## Role + Boot (required at session start)

Valid roles are exactly:

- `CHAD` (human)
- `DEV`
- `DATA`
- `STRAT`

If the user’s first message is a role statement (examples: “you are strat”,
“you are dev”, “set role data”), treat it as **role selection** for the session.

After role is set, boot immediately by fetching these four Orbit docs (canonical
IDs; no duplicates):

1) `boot-protocol`
2) `roles`
3) `role-boundaries`
4) `charter`

**Boot Protocol v2 (alias-first):** use the MCP tool `mcp__camber__fetch` in
this order:
- `id="b"`; fallback `id="boot-protocol"`
- `id="r"`; fallback `id="roles"`
- `id="rb"`; fallback `id="role-boundaries"`
- `id="c"`; fallback `id="charter"`

Only if MCP fetch is blocked / not_found / unavailable for the session, fall
back to local disk reads from `/Users/chadbarlow/gh/hcb-gpt/orbit/docs/`.
**Do not read local files during boot unless MCP fetch fails.**

Do **not** fetch `founding-policies` during boot; it is legacy and must not be
required.

If any boot fetch fails (blocked, not_found, empty), stop and report the
failure via TRAM to `STRAT` (use `kind=test`, `priority=high`, `thread=boot`)
including origin metadata and the exact error text.

