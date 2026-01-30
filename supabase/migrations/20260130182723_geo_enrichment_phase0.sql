-- Migration: Geo Enrichment Schema (Phase 0)
--
-- POLICY CONSTRAINT (DO NOT REMOVE):
-- Geo proximity is a WEAK signal. It may inform candidate ranking and
-- review triage, but it can NEVER justify decision='assign' without a
-- strong transcript-grounded anchor quote (project name, alias, address
-- fragment, or client name).
--
-- This schema provides foundation for geo-enrichment. No behavioral
-- changes to context-assembly or ai-router in this migration.

-- =============================================================================
-- Table 1: project_geo
-- Project coordinates for distance calculations. 1:1 with projects table.
-- =============================================================================
CREATE TABLE IF NOT EXISTS project_geo (
  project_id UUID PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL,
  geocode_source TEXT NOT NULL,           -- 'google'|'mapbox'|'manual'|'batch'
  geocode_precision TEXT NULL,            -- 'rooftop'|'range'|'zip'|'city'
  geocoded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE project_geo IS
  'Project coordinates for geo-enrichment. POLICY: Geo proximity is a WEAK signal - never sufficient alone for auto-assign. Requires strong transcript-grounded anchor.';

COMMENT ON COLUMN project_geo.geocode_source IS
  'Provider or method used: google, mapbox, manual, batch';

COMMENT ON COLUMN project_geo.geocode_precision IS
  'Accuracy level: rooftop (exact), range (interpolated), zip (centroid), city (centroid)';

-- =============================================================================
-- Table 2: geo_places
-- Local gazetteer for resolving place names mentioned in transcripts.
-- Cached lookups to avoid repeated geocoding API calls.
-- =============================================================================
CREATE TABLE IF NOT EXISTS geo_places (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  state TEXT NULL,                        -- e.g., 'GA'
  country TEXT NOT NULL DEFAULT 'US',
  lat DOUBLE PRECISION NOT NULL,
  lon DOUBLE PRECISION NOT NULL,
  source TEXT NOT NULL,                   -- 'geonames'|'census'|'google'|'manual'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Uniqueness constraint on (lower(name), state) to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS geo_places_name_state_uq
  ON geo_places (LOWER(name), COALESCE(state, ''));

COMMENT ON TABLE geo_places IS
  'Gazetteer for place name resolution. Populate from trusted sources (GeoNames, Census) or manual entry. POLICY: Geo is a weak signal only.';

COMMENT ON COLUMN geo_places.source IS
  'Data source: geonames, census, google, manual. Document provenance for auditability.';

-- =============================================================================
-- NOTE: span_place_mentions table deferred until Phase 1
-- (extraction implementation). Keeps DB surface minimal until actually used.
-- =============================================================================

-- Enable RLS on both tables (no policies = service-role only access)
ALTER TABLE project_geo ENABLE ROW LEVEL SECURITY;
ALTER TABLE geo_places ENABLE ROW LEVEL SECURITY;;
