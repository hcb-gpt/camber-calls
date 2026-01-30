
-- override_log: enable composite key support for affinity edges
-- Prerequisite: table is empty (verified), safe to alter constraints

-- 1) Allow entity_id to be null (required for XOR to work)
alter table public.override_log
  alter column entity_id drop not null;

-- 2) Add composite key column
alter table public.override_log
  add column if not exists entity_key text;

-- 3) Enforce exactly one of (entity_id, entity_key)
alter table public.override_log
  drop constraint if exists override_log_entity_id_xor_entity_key;

alter table public.override_log
  add constraint override_log_entity_id_xor_entity_key
  check (
    (entity_id is not null and entity_key is null)
    or
    (entity_id is null and entity_key is not null)
  );

-- 4) Index for analytics / lookups on composite keys
create index if not exists override_log_entity_key_idx
  on public.override_log(entity_key);

-- Convention: composite keys use colon delimiter, alphabetical entity order
-- Example: correspondent_project_affinity → '<contact_uuid>:<project_uuid>'
;
