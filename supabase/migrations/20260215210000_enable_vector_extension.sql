-- Enable pgvector 0.8.0 for semantic search
-- Applied by DATA-2 session, 2026-02-15
CREATE EXTENSION IF NOT EXISTS vector
  WITH SCHEMA extensions;
