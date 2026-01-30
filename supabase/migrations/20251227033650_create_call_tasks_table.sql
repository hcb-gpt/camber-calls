
CREATE TABLE IF NOT EXISTS call_tasks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id  TEXT NOT NULL,
    task_text       TEXT NOT NULL,
    due_date        DATE,
    owner           TEXT,
    priority        TEXT,
    status          TEXT NOT NULL DEFAULT 'open',
    source          TEXT NOT NULL DEFAULT 'ai',
    created_at_utc  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at_utc  TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- FK to interactions (interaction_id is UNIQUE there)
    CONSTRAINT fk_call_tasks_interaction 
        FOREIGN KEY (interaction_id) 
        REFERENCES interactions(interaction_id) 
        ON DELETE CASCADE,
    
    -- Idempotency: same task text for same interaction = one row
    CONSTRAINT call_tasks_interaction_task_key 
        UNIQUE (interaction_id, task_text),
    
    -- Status enum check
    CONSTRAINT call_tasks_status_check 
        CHECK (status IN ('open', 'done', 'snoozed'))
);

COMMENT ON TABLE call_tasks IS 'AI-extracted tasks from calls, one row per task item';

-- Indexes for digest queries
CREATE INDEX IF NOT EXISTS idx_call_tasks_status ON call_tasks(status);
CREATE INDEX IF NOT EXISTS idx_call_tasks_due_date ON call_tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_call_tasks_created_at ON call_tasks(created_at_utc DESC);
CREATE INDEX IF NOT EXISTS idx_call_tasks_interaction ON call_tasks(interaction_id);
CREATE INDEX IF NOT EXISTS idx_call_tasks_open_due ON call_tasks(status, due_date) WHERE status = 'open';
;
