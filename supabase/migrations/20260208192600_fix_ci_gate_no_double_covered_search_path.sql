-- Fix schema-resolution runtime failures from SECURITY DEFINER funcs with empty search_path
-- and unqualified table references.
--
-- Incident A:
--   ci_gate_no_double_covered() failed inside ci_run_all_gates() with
--   `relation "conversation_spans" does not exist` even though table exists in public.
-- Incident B:
--   proof_interaction_scoreboard(text) failed with same error path.

ALTER FUNCTION IF EXISTS public.ci_gate_no_double_covered()
  SET search_path TO public;

ALTER FUNCTION IF EXISTS public.proof_interaction_scoreboard(text)
  SET search_path TO public;
