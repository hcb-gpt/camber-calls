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
