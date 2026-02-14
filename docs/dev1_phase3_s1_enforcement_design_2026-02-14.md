# DEV-1 Phase 3 Design: S1 Enforcement + Claim Pointer Contract

Date: 2026-02-14
Owner: DEV-1
Receipt target: `dev1_phase3_s1_enforcement_design`

## Goal
Enforce canon invariant "Pointers or it isn't a belief" at DB and application layers before Phase 3 implementation work.

## Current-State Audit (live)
- `belief_claims` total: **70**
- `belief_claims` with >=1 `claim_pointers` row: **67**
- `belief_claims` without pointer row: **3**
- `claim_pointers` total rows: **106**

### Structural gap found
Current `promote_journal_claims_to_belief` creates `claim_pointers` with `ts_start/ts_end=NULL` and does not guarantee valid char locator in the inserted pointer row. This does not satisfy canonical pointer validity.

## Design Principles
- Claim-level attribution only; no call-level forced project assignment.
- Valid pointer means at least one locator path is usable:
  - char locator: `char_start` + `char_end` with `char_end > char_start`
  - OR time locator: `ts_start` + `ts_end` with `ts_end > ts_start`
- Enforcement must be transaction-safe and idempotent.
- Existing pointerless claims must be repaired or demoted before hard enforcement.

## DB Enforcement Design (S1)

### 1) Pointer validity helper
Add helper function:
- `public.is_valid_claim_pointer(cp claim_pointers)` returns boolean
- true when either valid char locator or valid time locator exists.

### 2) Deferrable S1 trigger on `belief_claims`
Add constraint trigger:
- Name: `trg_belief_claim_has_valid_pointer`
- Timing: `AFTER INSERT OR UPDATE` on `belief_claims`
- Mode: `DEFERRABLE INITIALLY DEFERRED`
- Behavior:
  - allow temporary states only for explicit non-promoted epistemics (`unsafe_no_receipts`, `draft`)
  - otherwise require at least one `claim_pointers` row for `new.id` passing validity helper
  - raise exception on commit if violated

### 3) Optional guard trigger on `claim_pointers`
Add row trigger to reject pointer inserts with neither valid char nor valid time locator.

### 4) Backward-compat rollout switch
Use a gated rollout to avoid breaking current prod writes:
- Phase A: create helper + observability query only
- Phase B: repair/demote existing invalid claims
- Phase C: enable deferrable trigger

## Application-Layer Enforcement Design

### 1) Promotion RPC contract hardening
Update `promote_journal_claims_to_belief` to create canonical pointer rows from `journal_claims`:
- `claim_id = new belief_claim id`
- `source_type = transcript_text`
- `source_id = journal_claims.call_id`
- char locator from `journal_claims.char_start`, `journal_claims.char_end`
- `span_text`, `span_hash` copied from `journal_claims` where available
- fallback to time locator only if char locator unavailable and times valid

### 2) Same-transaction guarantee
`belief_claims` insert and `claim_pointers` insert must occur in one transaction so deferred trigger validates at commit.

### 3) Write-path boundary
Disallow ad hoc writes to `belief_claims` from edge functions.
- Promote only via approved RPC path(s).
- Add static check in edge functions for direct `from("belief_claims")` writes (CI guard).

## Repair Plan for Existing Data

For existing pointerless `belief_claims` (currently 3):
1. Attempt pointer backfill from linked `journal_claims` (via `journal_claim_id`) using char locator + span data.
2. If no recoverable pointer evidence, demote:
   - set `epistemic_status='unsafe_no_receipts'`
   - add repair note (new audit table or promotion log extension)
3. Re-run readiness query until `without_pointer = 0` for promoted claims.

## Acceptance Criteria
- Inserting promoted `belief_claims` without valid pointer fails at commit.
- Inserting claim + valid pointer in same txn succeeds.
- Existing promoted claims have valid pointer coverage (or are explicitly demoted).
- Promotion function emits valid char/time locator pointers consistently.

## SQL Skeleton (for implementation phase)
```sql
create or replace function public.enforce_belief_claim_has_valid_pointer()
returns trigger language plpgsql as $$
begin
  if new.epistemic_status in ('unsafe_no_receipts','draft') then
    return new;
  end if;

  if not exists (
    select 1
    from public.claim_pointers cp
    where cp.claim_id = new.id
      and (
        (cp.char_start is not null and cp.char_end is not null and cp.char_end > cp.char_start)
        or
        (cp.ts_start is not null and cp.ts_end is not null and cp.ts_end > cp.ts_start)
      )
  ) then
    raise exception 'S1 violation: belief_claim % has no valid pointer', new.id;
  end if;

  return new;
end;
$$;

create constraint trigger trg_belief_claim_has_valid_pointer
after insert or update on public.belief_claims
deferrable initially deferred
for each row execute function public.enforce_belief_claim_has_valid_pointer();
```

## Risks / Open Questions
- Some historical claims may lack recoverable span evidence; policy decision needed on demotion semantics logging.
- If any non-promotion workflow writes `belief_claims` directly, enforcement will surface hidden coupling quickly.
