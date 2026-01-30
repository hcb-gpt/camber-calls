-- Drop unused indexes on belief/journal system tables (flagged by advisor)

-- belief_claims (68 rows, indexes never used)
DROP INDEX IF EXISTS idx_belief_claims_lifecycle;
DROP INDEX IF EXISTS idx_belief_claims_event_at;
DROP INDEX IF EXISTS idx_belief_claims_confidence;

-- belief_open_loops (empty)
DROP INDEX IF EXISTS idx_belief_open_loops_status;
DROP INDEX IF EXISTS idx_belief_open_loops_due;

-- claim_pointers (104 rows, index never used)
DROP INDEX IF EXISTS idx_claim_pointers_source;

-- journal_conflicts (2 rows)
DROP INDEX IF EXISTS idx_journal_conflicts_run;
DROP INDEX IF EXISTS idx_journal_conflicts_unresolved;

-- journal_open_loops (70 rows)
DROP INDEX IF EXISTS idx_journal_open_loops_run;
DROP INDEX IF EXISTS idx_journal_open_loops_open;;
