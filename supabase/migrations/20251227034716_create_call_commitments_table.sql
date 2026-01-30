
CREATE TABLE IF NOT EXISTS call_commitments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    interaction_id          TEXT NOT NULL,
    title                   TEXT NOT NULL,
    start_iso               TIMESTAMPTZ,
    end_iso                 TIMESTAMPTZ,
    timezone                TEXT,
    duration_minutes        INTEGER,
    participants            TEXT[],
    location                TEXT,
    notes                   TEXT,
    confidence              NUMERIC,
    source_snippet          TEXT,
    needs_clarification     BOOLEAN NOT NULL DEFAULT false,
    clarifying_questions    TEXT[],
    status                  TEXT NOT NULL DEFAULT 'open',
    created_at_utc          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at_utc          TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- FK to interactions
    CONSTRAINT fk_call_commitments_interaction 
        FOREIGN KEY (interaction_id) 
        REFERENCES interactions(interaction_id) 
        ON DELETE CASCADE,
    
    -- Status enum check
    CONSTRAINT call_commitments_status_check 
        CHECK (status IN ('open', 'confirmed', 'cancelled', 'done'))
);

COMMENT ON TABLE call_commitments IS 'Calendar commitments extracted from calls - scheduling items that need follow-up';

-- Idempotency: unique on (interaction_id, title, start_iso) for non-null start_iso
CREATE UNIQUE INDEX IF NOT EXISTS idx_call_commitments_unique_with_start 
    ON call_commitments(interaction_id, title, start_iso) 
    WHERE start_iso IS NOT NULL;

-- Idempotency: unique on (interaction_id, title) for null start_iso
CREATE UNIQUE INDEX IF NOT EXISTS idx_call_commitments_unique_null_start 
    ON call_commitments(interaction_id, title) 
    WHERE start_iso IS NULL;

-- Query indexes
CREATE INDEX IF NOT EXISTS idx_call_commitments_start ON call_commitments(start_iso);
CREATE INDEX IF NOT EXISTS idx_call_commitments_status_start ON call_commitments(status, start_iso);
CREATE INDEX IF NOT EXISTS idx_call_commitments_interaction ON call_commitments(interaction_id);
CREATE INDEX IF NOT EXISTS idx_call_commitments_open_upcoming 
    ON call_commitments(start_iso) 
    WHERE status = 'open';
;
