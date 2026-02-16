-- Woodbery Residence: project_facts seed (v0) with strict provenance via evidence_events (source_type='manual').
--
-- Derived from:
-- - orbit/orbit/docs/camber/world_model/inputs/2026-02-16/woodbery/woodbery_plans_fact_pack_v0.json
--
-- IMPORTANT
-- - This file MUTATES DATA. Do NOT run via `scripts/query.sh` (read-only guard).
-- - Run via psql (or equivalent) with appropriate credentials:
--     psql "$DATABASE_URL" -f scripts/backfills/woodbery_seed_v0.sql
-- - This script ends with ROLLBACK by default. To apply, change to COMMIT intentionally.
--
-- Goal
-- - Seed plan-derived disambiguators for Woodbery so attribution can use time-aware evidence packs.
-- - Every fact carries strict provenance via a single manual evidence_events row.
-- - IMPORTANT TIME NOTE:
--     observed_at is set to as_of_at so KNOWN_AS_OF retrieval can use plan facts for historical calls
--     after the plan issue date (simulation of “we knew this as-of the plan issue”).
--
begin;

with params as (
  select
    '7db5e186-7dda-4c2c-b85e-7235b67e06d8'::uuid as project_id,
    '2025-09-04T00:00:00Z'::timestamptz as as_of_at,
    '2025-09-04T00:00:00Z'::timestamptz as observed_at,
    ('manual_seed:woodbery_residence_v0:' || encode(gen_random_bytes(8), 'hex'))::text as source_id
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
      'seed_script', 'scripts/backfills/woodbery_seed_v0.sql',
      'seed_kind', 'woodbery_residence_project_facts_v0',
      'source_file', 'orbit/orbit/docs/camber/world_model/inputs/2026-02-16/woodbery/woodbery_plans_fact_pack_v0.json',
      'project_code', 'WOODBERY',
      'notes', 'Plan-derived disambiguator facts for Woodbery Residence (review set).'
    )
  from params p
  returning evidence_event_id
),
seed_facts as (
  select 'scope.site'::text as fact_kind,
    jsonb_build_object(
      'feature','site.address.full',
      'value','2190 Enterprise Road, Madison, GA 30650',
      'tags',jsonb_build_array('PLANS_GT'),
      'confidence',0.98,
      'notes','From title block',
      'source_ref',jsonb_build_object('sheet','A1-1','page',2)
    ) as fact_payload
  union all select 'scope.feature',
    jsonb_build_object('feature','site.alias.primary','value','Enterprise','tags',jsonb_build_array('PLANS_GT','ALIAS'),'confidence',0.90,'notes','Primary site alias','source_ref',jsonb_build_object('sheet','A1-1','page',2))
  union all select 'scope.document',
    jsonb_build_object('feature','plan.issue_date','value','2025-09-04','tags',jsonb_build_array('PLANS_GT'),'confidence',1.0,'notes','Review set issue date')
  union all select 'scope.document',
    jsonb_build_object('feature','plan.revision_label','value','review_set','tags',jsonb_build_array('PLANS_GT'),'confidence',0.88,'notes','Plan set family')
  union all select 'scope.contact',
    jsonb_build_object('feature','plan.architect.firm','value','Greg Busch Architects AIA','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Architect firm')

  union all select 'scope.feature',
    jsonb_build_object('feature','building.levels.count','value',2,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.95,'notes','Main + upper levels','source_ref',jsonb_build_object('sheets',jsonb_build_array('A1-1','A1-2'),'pages',jsonb_build_array(2,3)))
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.heated_total','value',5304,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.95,'notes','Area summary')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.heated_main','value',2928,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.92,'notes','Heated main area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.heated_upper','value',1285,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.92,'notes','Heated upper area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.garage_attached_unheated','value',640,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Garage area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.porch_stoop','value',554,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.89,'notes','Porch+stoop area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.patio','value',152,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.89,'notes','Patio area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','building.sqft.under_roof_total_est','value',5407,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.88,'notes','Under-roof total estimate')
  union all select 'scope.dimension',
    jsonb_build_object('feature','garage.floor_below_main','value',18,'unit','inches','tags',jsonb_build_array('PLANS_GT'),'confidence',0.86,'notes','Garage floor drop below main')

  union all select 'scope.dimension',
    jsonb_build_object('feature','exterior.area.screened_porch_sqft','value',597,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.91,'notes','Screened porch area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','exterior.area.grilling_porch_sqft','value',134,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Grilling porch area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','exterior.area.terrace_sqft','value',597,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.88,'notes','Terrace area')
  union all select 'scope.dimension',
    jsonb_build_object('feature','exterior.area.garage_sqft','value',667,'unit','sqft','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Garage footprint')

  union all select 'scope.feature',
    jsonb_build_object('feature','garage.parking.count','value',2,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.94,'notes','2-car garage parking')
  union all select 'scope.feature',
    jsonb_build_object('feature','foundation.system','value','crawlspace + slab_on_grade (garage) + slab_on_grade (porch)','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Mixed foundation discriminator')
  union all select 'scope.site',
    jsonb_build_object('feature','roof.pitch.main','value','8/12','tags',jsonb_build_array('PLANS_GT'),'confidence',0.85,'notes','Main roof pitch')
  union all select 'scope.site',
    jsonb_build_object('feature','roof.pitch.low_slope','value','1.5/12','tags',jsonb_build_array('PLANS_GT'),'confidence',0.85,'notes','Low-slope roof area pitch')
  union all select 'scope.material',
    jsonb_build_object('feature','roof.material.primary','value','cedar_shake','tags',jsonb_build_array('PLANS_GT'),'confidence',0.86,'notes','Primary roof material')
  union all select 'scope.material',
    jsonb_build_object('feature','roof.material.secondary','value','metal','tags',jsonb_build_array('PLANS_GT'),'confidence',0.86,'notes','Secondary roof material')
  union all select 'scope.material',
    jsonb_build_object('feature','envelope.window.material','value','steel','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Steel windows explicitly called out')
  union all select 'scope.dimension',
    jsonb_build_object('feature','envelope.window.oval.quantity','value',2,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.89,'notes','Oval window quantity')
  union all select 'scope.feature',
    jsonb_build_object('feature','openings.living_room.door_package','value','18'' x 10'' six-panel sliders','tags',jsonb_build_array('PLANS_GT'),'confidence',0.88,'notes','Distinctive sliding door package')

  union all select 'scope.feature',
    jsonb_build_object('feature','space.scullery.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.98,'notes','SCULLERY labeled')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.screened_porch.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.98,'notes','SCREENED PORCH labeled')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.grilling_porch.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.96,'notes','GRILLING PORCH labeled')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.coffee_dressing.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.97,'notes','Coffee/dressing room exists')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.pool_bath.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.94,'notes','Pool bath labeled')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.bar.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.93,'notes','Bar space exists')
  union all select 'scope.feature',
    jsonb_build_object('feature','space.study_den.exists','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.92,'notes','Study/den exists')
  union all select 'scope.feature',
    jsonb_build_object('feature','feature.motorized_screens','value',true,'tags',jsonb_build_array('PLANS_GT'),'confidence',0.95,'notes','Motorized screens disambiguator')
  union all select 'scope.dimension',
    jsonb_build_object('feature','feature.outdoor_kitchen.grill_width_in','value',42,'unit','in','tags',jsonb_build_array('PLANS_GT'),'confidence',0.90,'notes','Built-in grill width')
  union all select 'scope.site',
    jsonb_build_object('feature','ceiling.vaulted_spaces','value','Dining room; Bedroom #1; Home gym; Upper sitting','tags',jsonb_build_array('PLANS_GT'),'confidence',0.85,'notes','Vaulted spaces list')
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
rollback;

