# Project Schema Enhancement Proposal
**DATA Analysis | 2026-02-13**

---

## Current State Audit

### `projects` table (19 rows, 31 columns)
Core identity, address, client info, permit jurisdiction, zoning, construction phase FK, contract value, septic_info (jsonb).

### Satellite tables already connected:
| Table | Rows | Purpose |
|-------|------|---------|
| `project_building_specs` | 1 | Sqft, beds, baths, garage, foundation, fireplace, porch |
| `project_permits` | 25 | Permit type/status/jurisdiction tracking |
| `project_contacts` | 260 | Vendor/sub ↔ project assignments |
| `project_clients` | 27 | Client contacts (primary/secondary) |
| `project_aliases` | 111 | Name variations for attribution |
| `project_memories` | 6 | Narrative/decision/open_item per project |
| `project_timeline_events` | 812 | Append-only factual timeline |
| `project_geo` | 15 | Lat/lon coordinates |
| `project_attribution_blocklist` | 3 | Block auto-attribution |
| `correspondent_project_affinity` | 336 | Contact-project relationship strength |
| `construction_phases` | 10 | Reference table (0000–9000) |

---

## Gap Analysis

### What the spec docs reveal is NOT captured:

The Moss and Hurley Licensed Trades Specs Extracts contain structured data about plumbing fixtures, HVAC constraints, electrical requirements, insulation R-values, ceiling heights, and coordination checklists. Most of this is **too granular** for relational columns — it belongs in `project_memories` as narrative/decision records. But several things are genuinely missing at the structural level.

### Critical gaps on `projects` table:

1. **Zero date tracking.** No `start_date` or `target_completion_date`. Every project has these. Currently the only temporal data is `created_at` (when the row was made).

2. **No utility infrastructure classification.** `water_source` (well vs municipal) and `sewer_type` (septic vs municipal) affect every trade's scope. The `septic_info` jsonb exists but is unstructured and only tells you about existing systems, not the project's actual sewer strategy.

3. **No lot/land metadata.** `acreage` matters for site work, NOI/erosion permits, and septic design on every new build.

4. **No pool flag.** Hurley has a 16'x32' pool + pool house. Pools affect electrical, plumbing, and permitting significantly but there's nowhere to record this.

5. **No plan set linkage.** The spec extracts reference specific plan sets (MOSS_Build Plans.pdf, HURLEY Building Plans.pdf) but there's no document tracking table.

### Gaps on `project_building_specs`:

6. **No insulation specs.** Both spec docs reference R-values (R-20 walls, R-38 roof for Hurley). These are energy code compliance data that every project needs.

7. **No ceiling heights.** Both docs detail ceiling heights extensively (10' main, 9' upper, 11'6" garage, vaulted spaces). Critical for HVAC sizing and electrical coordination.

8. **No mechanical system summary.** HVAC zone count, AHU count, equipment locations — affects coordination.

---

## Proposal: Three Tiers

### Tier 1: Add to `projects` table (6 columns)

These apply to every project. Low bloat because they're filterable/queryable dimensions.

```sql
ALTER TABLE projects
  ADD COLUMN start_date date,
  ADD COLUMN target_completion_date date,
  ADD COLUMN water_source text CHECK (water_source IN ('well', 'municipal', 'spring', 'other')),
  ADD COLUMN sewer_type text CHECK (sewer_type IN ('septic', 'municipal', 'other')),
  ADD COLUMN has_pool boolean DEFAULT false,
  ADD COLUMN acreage numeric;

COMMENT ON COLUMN projects.start_date IS 'Construction start date (not contract signing)';
COMMENT ON COLUMN projects.target_completion_date IS 'Target substantial completion date';
COMMENT ON COLUMN projects.water_source IS 'Water supply: well, municipal, spring, other';
COMMENT ON COLUMN projects.sewer_type IS 'Sewer system: septic, municipal, other. Complements septic_info jsonb.';
COMMENT ON COLUMN projects.has_pool IS 'Whether project includes pool construction. Affects electrical, plumbing, permits.';
COMMENT ON COLUMN projects.acreage IS 'Lot size in acres. Relevant for site work, NOI, erosion permits.';
```

**Why these 6 and not more:** Each is a dimension you'd realistically filter by ("show me all septic projects", "what's our active acreage", "projects starting Q1"), and each affects trade scope across the board.

### Tier 2: Extend `project_building_specs` (5 columns)

These are building-envelope data that the spec docs show are needed for trade coordination.

```sql
ALTER TABLE project_building_specs
  ADD COLUMN insulation_wall_r numeric,
  ADD COLUMN insulation_roof_r numeric,
  ADD COLUMN ceiling_height_main_ft numeric,
  ADD COLUMN ceiling_height_upper_ft numeric,
  ADD COLUMN has_vaulted_spaces boolean DEFAULT false;

COMMENT ON COLUMN project_building_specs.insulation_wall_r IS 'Exterior wall R-value (e.g., 20 for R-20)';
COMMENT ON COLUMN project_building_specs.insulation_roof_r IS 'Roof assembly R-value (e.g., 38 for R-38)';
COMMENT ON COLUMN project_building_specs.ceiling_height_main_ft IS 'Predominant main level ceiling height in feet';
COMMENT ON COLUMN project_building_specs.ceiling_height_upper_ft IS 'Predominant upper level ceiling height in feet';
COMMENT ON COLUMN project_building_specs.has_vaulted_spaces IS 'Whether project has vaulted/cathedral ceilings. HVAC coordination flag.';
```

### Tier 3: New `project_documents` table

There's no document tracking anywhere. Plan sets, spec extracts, permit applications, contracts, change orders — all floating in Drive with no DB linkage. This is lightweight and avoids duplicating document content.

```sql
CREATE TABLE project_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES projects(id),
  doc_type text NOT NULL CHECK (doc_type IN (
    'plan_set', 'spec_extract', 'permit_app', 'contract',
    'change_order', 'proposal', 'survey', 'soil_report',
    'energy_compliance', 'other'
  )),
  title text NOT NULL,
  drive_file_id text,
  url text,
  version text,
  page_count integer,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_project_documents_project ON project_documents(project_id);
CREATE INDEX idx_project_documents_type ON project_documents(doc_type);

COMMENT ON TABLE project_documents IS
  'Lightweight document registry linking projects to their plan sets, specs, permits, and contracts. Does not store document content — just metadata and Drive/URL references.';

ALTER TABLE project_documents ENABLE ROW LEVEL SECURITY;
```

---

## What I Deliberately Excluded (Anti-Bloat)

| Considered | Why excluded |
|-----------|--------------|
| Room-by-room specs (ceiling heights per room, fixtures per bath) | Too granular. Use `project_memories` with type='narrative' |
| Appliance schedule (range model, water heater type, fixture brands) | Too volatile. Changes with owner selections. Better as narrative memory or document reference |
| Trade-specific coordination checklists | Already captured as spec extract documents |
| `electrical_service_amps`, `hvac_zone_count`, `water_heater_type` | Only known late in pre-construction. Would sit NULL on most rows. If needed later, extend `project_building_specs` |
| `energy_code_compliance_path` (prescriptive vs performance) | Only 2 values across all projects, not worth a column yet |
| `architect`, `engineer` columns on projects | Already represented in `project_contacts` with role |
| `contract_signed_date`, `closing_date` | Can live in `project_timeline_events` (append-only is better for these) |
| Separate `project_trade_specs` junction table | Premature. The spec docs are better as documents + memories until we have a clear query pattern |

---

## Net Impact

| Change | Columns Added | Tables Added | Migration Risk |
|--------|--------------|--------------|----------------|
| Tier 1: projects | +6 | 0 | None (all nullable, additive) |
| Tier 2: project_building_specs | +5 | 0 | None (all nullable, additive) |
| Tier 3: project_documents | 0 (on existing) | +1 | Low (new table, no FK changes) |
| **Total** | **+11** | **+1** | **Low** |

All changes are additive, nullable, and backwards-compatible. No existing queries break.

---

## Recommended Backfill Priority

Once schema is applied:
1. Backfill `sewer_type` and `water_source` for all 19 projects (quick manual pass)
2. Backfill `start_date` for active projects from BuilderTrend or `project_timeline_events`
3. Create `project_documents` rows for the Moss and Hurley plan sets + spec extracts
4. Populate `project_building_specs` rows for Hurley (currently only Moss has one)
5. Extend Moss building specs with insulation and ceiling height data from the spec extract
