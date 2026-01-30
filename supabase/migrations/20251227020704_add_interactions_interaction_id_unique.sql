
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'interactions_interaction_id_key'
    ) THEN
        ALTER TABLE interactions ADD CONSTRAINT interactions_interaction_id_key UNIQUE (interaction_id);
    END IF;
END $$;
;
