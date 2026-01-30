# Release History

## 2026-01-30 (Commit: ed8af8a)

### Edge Functions Deployed
| Function | Version | Prompt | Supabase ID |
|----------|---------|--------|-------------|
| ai-router | v10 | v1.5.0 | 835ef3d7-9b32-45f0-82ac-7c894e203a8f |
| context-assembly | v3 | v1.0.1 | (deployed via MCP) |

### Changes in ai-router v1.5.0
- Lock monotonicity: human > ai > null
- Quote guardrail: substring validation + text-quote coherence
- Staff name filtering: programmatic rejection of HCB staff names as anchors
- Weak anchor policy: city/zip alone → decision=review, never assign
- Prompt updates: staff exclusion rules, anchor strength policy

### Changes in context-assembly v1.0.1
- Added try/catch for missing `v_project_alias_lookup` view
- Logs warning, continues without alias expansion

### Schema: Geo Enrichment Phase 0
- Migration: `20260130182723_geo_enrichment_phase0.sql`
- Tables: `project_geo`, `geo_places` (empty, RLS enabled)
- Policy: Geo is weak signal only, never sufficient for auto-assign

### Migration Baseline Import
- 393 migration files imported via `supabase migration fetch`
- Range: 20251207211945 → 20260130182723
- Closes systemic drift gap (prod schema now tracked in Git)

---
