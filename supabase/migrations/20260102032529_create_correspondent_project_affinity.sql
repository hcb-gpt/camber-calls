
-- Phase 1: Affinity Engine table
CREATE TABLE correspondent_project_affinity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    weight NUMERIC DEFAULT 0,
    confirmation_count INT DEFAULT 0,
    rejection_count INT DEFAULT 0,
    last_interaction_at TIMESTAMPTZ,
    source TEXT DEFAULT 'inferred', -- 'manual', 'inferred', 'seeded'
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(contact_id, project_id)
);

-- Index for fast lookup by contact
CREATE INDEX idx_affinity_contact ON correspondent_project_affinity(contact_id);

-- Index for fast lookup by project
CREATE INDEX idx_affinity_project ON correspondent_project_affinity(project_id);

-- Index for getting top affinities
CREATE INDEX idx_affinity_weight ON correspondent_project_affinity(contact_id, weight DESC);

COMMENT ON TABLE correspondent_project_affinity IS 'Phase 1 Affinity Engine: Tracks correspondent-project relationship strength for auto-linking';
COMMENT ON COLUMN correspondent_project_affinity.weight IS 'Affinity score: +1 on confirm, -1 on reject, *0.98 weekly decay';
COMMENT ON COLUMN correspondent_project_affinity.source IS 'manual=human set, seeded=from project_clients, inferred=from patterns';
;
