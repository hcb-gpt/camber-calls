# AGENTS.md - Camber Calls (Local Agents)

## Role + Boot (required at session start)

Valid roles are exactly:

- `CHAD` (human)
- `DEV`
- `DATA`
- `STRAT`

If the user’s first message is a role statement (examples: “you are strat”,
“you are dev”, “set role data”), treat it as **role selection** for the session.

**Instance numbering:** when the user says “you are dev-3” or “you are data-2”,
parse the base role (`DEV`, `DATA`) as `SESSION_ROLE` and put the instance in
`origin_session` metadata (for example, `dev-3`). Do not treat numbered labels
as distinct roles.

**Reboot / refresh command (mid-session):** treat these as full boot refresh
commands without opening a new session:
- `reboot`
- `reboot as <role>` or `reboot as <role>-<instance>`
- `refresh role`
- `refresh as <role>` or `refresh as <role>-<instance>`

On reboot/refresh:
- Parse role + instance using the same role-selection rules.
- If no role is provided, keep current role and `origin_session`.
- If same role is provided, still run full refresh (policy refresh).
- Re-fetch boot docs, send fresh activation confirmation, then run
  `tram_unread` and `tram_work_items` before continuing.

**Capabilities in activation (required):** include:
- `CAPABILITIES_VERSION: v1`
- `CAPABILITIES:` comma-separated tags from
  `shell_cli,gcloud,mcp_supabase,mcp_github,mcp_drive,browser_ui,file_io`

**Structured roll call responses (required):** no free-text blobs. Use key/value
lines with:
- `ROLE`, `ORIGIN_SESSION`, `ORIGIN_PLATFORM`, `ORIGIN_CLIENT`, `ONLINE`
- `CURRENT_TASK`, `ETA_MIN`, `CAPABILITIES_VERSION`, `CAPABILITIES`, `BLOCKERS`

**STRAT routing rule:** for capability-constrained work, delegate only to online
sessions whose reported capabilities satisfy task requirements.

After role is set, boot immediately by fetching these four Orbit docs (no
duplicates):

- `boot-protocol`
- `roles`
- `role-boundaries`
- `charter`

Do **not** fetch `founding-policies` during boot; it is legacy and must not be
required.

If any boot fetch fails (blocked, not_found, empty), stop and report the
failure via TRAM to `STRAT` (use `kind=test`, `priority=high`, `thread=boot`)
including origin metadata and the exact error text.
