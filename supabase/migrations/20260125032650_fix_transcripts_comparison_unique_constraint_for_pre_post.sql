-- GATE 4 Fix: Allow PRE and POST variants to coexist for same (interaction_id, engine)
-- Drop existing constraint that only covers (interaction_id, engine)
ALTER TABLE transcripts_comparison 
DROP CONSTRAINT IF EXISTS transcripts_comparison_interaction_id_engine_key;

-- Create new constraint that includes transcript_variant
-- NULL variant counts as distinct, so Beside (variant=NULL) + Deepgram PRE + Deepgram POST can coexist
ALTER TABLE transcripts_comparison 
ADD CONSTRAINT transcripts_comparison_interaction_engine_variant_key 
UNIQUE (interaction_id, engine, transcript_variant);;
