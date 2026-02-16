-- Moss Residence: project_facts seed (v0) with strict provenance via evidence_events (source_type='manual').
--
-- Derived from: gandalf_project_MOSS_fields_values.json (plan-extracted data)
-- Template:     scripts/backfills/project_facts_seed_pilot_v0.sql (PR #105)
--
-- IMPORTANT
-- - This file MUTATES DATA. Do NOT run via `scripts/query.sh`.
-- - Run via psql (or equivalent) with appropriate credentials.
-- - This script ends with ROLLBACK by default. To apply, change to COMMIT intentionally.
--
-- Change ROLLBACK to COMMIT to apply.
--
-- Goal
-- - Seed ~25 high-signal, plan-derived facts for the Moss Residence project.
-- - Every fact carries strict provenance (evidence_event_id) from a manual evidence_events row.
-- - fact_kind taxonomy:
--     scope.feature   — building features (foundation, fireplaces, etc.)
--     scope.dimension — measurements (sqft, floors, bedrooms, etc.)
--     scope.material  — material specs (roof types, construction type)
--     scope.contact   — contacts (plan designer)
--     scope.site      — site/address info (jurisdiction, address)
--
-- After running (even in ROLLBACK), you can validate with:
-- - `scripts/sql/proofs/project_facts_missing_provenance.sql`
-- - `scripts/sql/proofs/project_facts_window_counts.sql`
-- - `scripts/sql/proofs/project_facts_seed_counts_by_kind.sql`
--
-- -----------------------------------------------------------------------------

begin;

with params as (
  select
    '47cb7720-9495-4187-8220-a8100c3b67aa'::uuid as project_id,
    '2025-09-01T04:00:00Z'::timestamptz          as as_of_at,
    now()::timestamptz                             as observed_at,
    ('manual_seed:moss_residence_v0:' || encode(gen_random_bytes(8), 'hex'))::text as source_id
),

manual_evidence as (
  insert into public.evidence_events (
    source_type,
    source_id,
    transcript_variant,
    occurred_at_utc,
    metadata
  )
  select
    'manual',
    p.source_id,
    null,
    p.as_of_at,
    jsonb_build_object(
      'seed_script',  'scripts/backfills/moss_residence_seed_v0.sql',
      'seed_kind',    'moss_residence_project_facts_v0',
      'source_file',  'gandalf_project_MOSS_fields_values.json',
      'project_code', 'MOSS',
      'notes',        'Plan-derived facts for Moss Residence. McKenzie Drafting plans, conservative as_of_at estimate.'
    )
  from params p
  returning evidence_event_id
),

seed_facts as (

  -- ==========================================================================
  -- scope.site — jurisdiction & address
  -- ==========================================================================

  select
    'scope.site'::text as fact_kind,
    jsonb_build_object(
      'feature',    'site.jurisdiction',
      'value',      'Town of North High Shoals, GA',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    ) as fact_payload

  union all select
    'scope.site',
    jsonb_build_object(
      'feature',    'site.address.line1',
      'value',      '619 New High Shoals Rd',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.site',
    jsonb_build_object(
      'feature',    'site.address.city',
      'value',      'Bishop',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.site',
    jsonb_build_object(
      'feature',    'site.address.state',
      'value',      'GA',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  union all select
    'scope.site',
    jsonb_build_object(
      'feature',    'site.structure_use',
      'value',      'Residential',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  -- ==========================================================================
  -- scope.dimension — counts & sqft
  -- ==========================================================================

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.floors_count',
      'value',      2,
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.bedrooms_count',
      'value',      4,
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.bathrooms_full_count',
      'value',      3,
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.bathrooms_half_count',
      'value',      1,
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_heated_total',
      'value',      4213,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_heated_main',
      'value',      2928,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_heated_upper',
      'value',      1285,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_garage_attached_unheated',
      'value',      640,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_porch_stoop',
      'value',      554,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_patio',
      'value',      152,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.sqft_under_roof_total_est',
      'value',      5407,
      'unit',       'sqft',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.90
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.garage_ceiling_height',
      'value',      '11''6"',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.dimension',
    jsonb_build_object(
      'feature',    'dimension.garage_floor_below_main_inches',
      'value',      18,
      'unit',       'inches',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  -- ==========================================================================
  -- scope.feature — building features
  -- ==========================================================================

  union all select
    'scope.feature',
    jsonb_build_object(
      'feature',    'feature.fireplaces_count',
      'value',      1,
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.feature',
    jsonb_build_object(
      'feature',    'feature.foundation_type',
      'value',      'Crawlspace (block)',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.feature',
    jsonb_build_object(
      'feature',    'feature.foundation_wall_notes',
      'value',      'Typical wall detail shows 8" concrete block foundation',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.90
    )

  union all select
    'scope.feature',
    jsonb_build_object(
      'feature',    'feature.permit_application_fee_usd',
      'value',      100,
      'unit',       'USD',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  -- ==========================================================================
  -- scope.material — construction & roof specs
  -- ==========================================================================

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.construction_primary',
      'value',      'Frame',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.construction_secondary_notes',
      'value',      'Brick elements shown in elevations/wall detail',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.90
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_pitch_main',
      'value',      '6/12',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_pitch_gables',
      'value',      '10/12',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_pitch_transitions',
      'value',      '3.75/12',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_pitch_porch_metal',
      'value',      '1.75/12',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_pitch_small_metal',
      'value',      '1/12',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.93
    )

  union all select
    'scope.material',
    jsonb_build_object(
      'feature',    'material.roof_material_porch',
      'value',      'Metal',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.95
    )

  -- ==========================================================================
  -- scope.contact — plan designer
  -- ==========================================================================

  union all select
    'scope.contact',
    jsonb_build_object(
      'feature',    'contact.plan_designer_firm',
      'value',      'McKenzie Drafting - Custom Home Design',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  union all select
    'scope.contact',
    jsonb_build_object(
      'feature',    'contact.plan_designer_phone',
      'value',      '706-759-2146',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )

  union all select
    'scope.contact',
    jsonb_build_object(
      'feature',    'contact.plan_designer_email',
      'value',      'mckenziedrafting@windstream.net',
      'tags',       jsonb_build_array('PLANS_GT'),
      'confidence', 0.98
    )
)

insert into public.project_facts (
  project_id,
  as_of_at,
  observed_at,
  fact_kind,
  fact_payload,
  evidence_event_id
)
select
  p.project_id,
  p.as_of_at,
  p.observed_at,
  sf.fact_kind,
  sf.fact_payload,
  me.evidence_event_id
from params p
cross join manual_evidence me
join seed_facts sf on true;

-- Default: do not apply.
-- Change ROLLBACK to COMMIT to apply.
rollback;
