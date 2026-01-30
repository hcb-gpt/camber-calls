-- Drop more unused indexes (flagged by advisor)

-- scheduler_items
DROP INDEX IF EXISTS idx_scheduler_items_needs_review;

-- company_anchors (3 rows)
DROP INDEX IF EXISTS idx_company_anchors_location_city;

-- cost_code_taxonomy
DROP INDEX IF EXISTS idx_cost_code_taxonomy_parent_category;
DROP INDEX IF EXISTS idx_cost_code_taxonomy_parent_subcategory;

-- entity_relationship_candidates
DROP INDEX IF EXISTS idx_erc_confidence;

-- review_queue (keeping functional ones, dropping unused)
DROP INDEX IF EXISTS idx_review_queue_interaction;
DROP INDEX IF EXISTS idx_review_queue_created;

-- evidence_events (1 row)
DROP INDEX IF EXISTS idx_evidence_events_source_type;
DROP INDEX IF EXISTS idx_evidence_events_ingested_at;

-- project_attribution_blocklist (3 rows)
DROP INDEX IF EXISTS idx_project_attribution_blocklist_active;

-- material_signal_config
DROP INDEX IF EXISTS idx_material_signal_config_active;

-- transcription_vocab
DROP INDEX IF EXISTS idx_transcription_vocab_active;

-- project_aliases
DROP INDEX IF EXISTS idx_project_aliases_alias_trgm;

-- construction_phases
DROP INDEX IF EXISTS idx_construction_phases_code_int;

-- projects
DROP INDEX IF EXISTS idx_projects_current_construction_phase;;
