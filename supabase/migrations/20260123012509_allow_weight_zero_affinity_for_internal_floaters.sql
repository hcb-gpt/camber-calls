-- STRATA20 spec (DATA-23 Operation B): allow weight=0 seeding for internal/floaters
-- Trigger: trg_block_affinity_updates_internal_floater
-- Function: util.block_affinity_updates_for_internal_floater()

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
      using new.contact_id;
  elsif has_contact_type then
    execute 'select contact_type from public.contacts where id=$1'
      into ctype
      using new.contact_id;
  elsif has_floats then
    execute 'select coalesce(floats_between_projects,false) from public.contacts where id=$1'
      into floats
      using new.contact_id;
  end if;

  -- Modified behavior: allow weight=0 inserts/updates for internal/floaters.
  -- Block only positive-weight edges to prevent false affinity signal.
  if (lower(coalesce(ctype,''))='internal' or floats) and coalesce(new.weight, 0) > 0 then
    return null; -- skip insert/update silently
  end if;

  return new;
end;
$$;
;
