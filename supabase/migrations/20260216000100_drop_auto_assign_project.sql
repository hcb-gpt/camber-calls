-- Drop auto_assign_project RPC: Stopline 1 violation
-- "SSOT for routing output is span_attributions. interactions.project_id is
--  not AI truth and must not be written by AI."
-- This RPC wrote to interactions.project_id, violating Stopline 1.
-- ai-router handles attribution properly via span_attributions.
-- Only 47 of 789 interactions ever used this path.
DROP FUNCTION IF EXISTS public.auto_assign_project(text);
