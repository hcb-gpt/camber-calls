create or replace function public.match_contacts_by_names_or_aliases(names_lower text[])
returns table (
  id uuid,
  name text,
  contact_type text,
  is_internal boolean,
  match_rank integer
)
language sql
stable
as $$
  select
    c.id,
    c.name,
    c.contact_type,
    coalesce(c.is_internal, false) as is_internal,
    min(
      case
        when lower(c.name) = any(names_lower) then 0
        else 1
      end
    ) as match_rank
  from public.contacts c
  left join lateral unnest(coalesce(c.aliases, '{}'::text[])) a(alias) on true
  where lower(c.name) = any(names_lower)
     or lower(a.alias) = any(names_lower)
  group by c.id, c.name, c.contact_type, c.is_internal
  order by
    match_rank asc,
    (case when coalesce(c.is_internal,false) or lower(coalesce(c.contact_type,''))='internal' then 1 else 0 end) asc,
    c.name asc
  limit 25;
$$;;
