
ALTER TABLE project_memories 
ALTER COLUMN source_interaction_ids TYPE TEXT[] 
USING source_interaction_ids::TEXT[];
;
