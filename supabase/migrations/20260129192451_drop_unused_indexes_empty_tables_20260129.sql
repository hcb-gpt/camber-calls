-- Drop non-PK indexes on empty n8n tables (tables are empty, indexes serve no purpose)
DROP INDEX IF EXISTS idx_shadow_errors_interaction;
DROP INDEX IF EXISTS idx_shadow_errors_unresolved;
DROP INDEX IF EXISTS idx_shadow_created;
DROP INDEX IF EXISTS idx_shadow_export;
DROP INDEX IF EXISTS idx_shadow_interaction;
DROP INDEX IF EXISTS idx_shadow_match;
DROP INDEX IF EXISTS idx_shadow_run;

-- Drop non-PK indexes on empty vocab_hits
DROP INDEX IF EXISTS idx_vocab_hits_interaction;
DROP INDEX IF EXISTS idx_vocab_hits_term;;
