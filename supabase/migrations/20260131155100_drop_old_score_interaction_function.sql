-- Drop the old score_interaction function with 2 args
-- Applied via MCP: 2026-01-31T15:51Z
DROP FUNCTION IF EXISTS score_interaction(text, boolean);

-- The new single-arg version remains
