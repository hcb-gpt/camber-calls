
-- Freeze learning updates to correspondent_project_affinity for internal/floater contacts.
-- Effect: any INSERT/UPDATE attempts for internal/floater contacts are silently skipped

create schema if not exists util;

create or replace function util.block_affinity_updates_for_internal_floater()
returns trigger
language plpgsql
as $$
declare
  has_contact_type boolean;
  has_floats boolean;
  ctype text := null;
  floats boolean := false;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema='public' and table_name='contacts' and column_name='contact_type'
  ) into has_contact_type;

  select exists (
    select 1
    from information_schema.columns
    where table_schema='public' and table_name='contacts' and column_name='floats_between_projects'
  ) into has_floats;

  if has_contact_type and has_floats then
    execute 'select contact_type, coalesce(floats_between_projects,false) from public.contacts where id=$1'
      into ctype, floats
      using NEW.contact_id;
  elsif has_contact_type then
    execute 'select contact_type from public.contacts where id=$1'
      into ctype
      using NEW.contact_id;
  elsif has_floats then
    execute 'select coalesce(floats_between_projects,false) from public.contacts where id=$1'
      into floats
      using NEW.contact_id;
  end if;

  if lower(coalesce(ctype,''))='internal' or floats then
    return null; -- skip insert/update silently
  end if;

  return NEW;
end;
$$;

-- Trigger (idempotent)
drop trigger if exists trg_block_affinity_updates_internal_floater on public.correspondent_project_affinity;
create trigger trg_block_affinity_updates_internal_floater
before insert or update on public.correspondent_project_affinity
for each row execute function util.block_affinity_updates_for_internal_floater();
;
