-- TEMPORARY: Drop unique constraint on interaction_id for recon work
-- REVERT PLAN: ALTER TABLE public.interactions ADD CONSTRAINT interactions_interaction_id_key UNIQUE (interaction_id);
-- WARNING: Before reverting, must resolve any duplicate interaction_ids

ALTER TABLE public.interactions DROP CONSTRAINT interactions_interaction_id_key;;
