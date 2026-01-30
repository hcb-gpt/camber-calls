
CREATE TABLE project_memories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id),
  memory_type TEXT NOT NULL DEFAULT 'narrative',
  content JSONB NOT NULL,
  source_interaction_ids UUID[] NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  CONSTRAINT valid_memory_type CHECK (memory_type IN ('narrative', 'decision', 'open_item'))
);

CREATE INDEX idx_project_memories_project_id ON project_memories(project_id);
CREATE INDEX idx_project_memories_type ON project_memories(memory_type);
;
