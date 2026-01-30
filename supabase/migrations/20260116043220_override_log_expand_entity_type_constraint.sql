
-- Expand entity_type constraint to include project_contacts and affinity edges
alter table public.override_log
  drop constraint if exists chk_override_log_entity_type;

alter table public.override_log
  add constraint chk_override_log_entity_type
  check (entity_type = any (array[
    'interaction'::text,
    'scheduler_item'::text,
    'project_contacts'::text,
    'correspondent_project_affinity'::text
  ]));
;
