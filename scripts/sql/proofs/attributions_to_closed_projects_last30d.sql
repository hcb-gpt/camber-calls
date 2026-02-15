-- Closed-project exclusion proof (last 30d).
-- Shows how often spans from last 30d are attributed to projects that are closed.
-- Run: scripts/query.sh --file scripts/sql/proofs/attributions_to_closed_projects_last30d.sql

-- A) Attribution counts by project phase/status (last 30d interactions)
with spans as (
  select cs.id as span_id, cs.interaction_id
  from public.conversation_spans cs
  join public.interactions i on i.interaction_id = cs.interaction_id
  where
    cs.is_superseded = false
    and coalesce(i.event_at_utc, i.ingested_at_utc) >= (now() - interval '30 days')
),
attrs as (
  select sa.span_id, sa.project_id
  from public.span_attributions sa
  join spans s on s.span_id = sa.span_id
  where sa.project_id is not null
)
select
  coalesce(p.phase, '(null)') as phase,
  coalesce(p.status, '(null)') as status,
  count(*) as attributions_last30d
from attrs a
join public.projects p on p.id = a.project_id
group by 1, 2
order by attributions_last30d desc, phase asc, status asc;

-- B) Top contacts by count of spans attributed to closed projects (last 30d)
with spans as (
  select cs.id as span_id, cs.interaction_id
  from public.conversation_spans cs
  join public.interactions i on i.interaction_id = cs.interaction_id
  where
    cs.is_superseded = false
    and coalesce(i.event_at_utc, i.ingested_at_utc) >= (now() - interval '30 days')
),
attrs as (
  select sa.span_id, sa.project_id
  from public.span_attributions sa
  join spans s on s.span_id = sa.span_id
  where sa.project_id is not null
),
bad as (
  select s.interaction_id
  from attrs a
  join spans s on s.span_id = a.span_id
  join public.projects p on p.id = a.project_id
  where p.phase = 'closed' or p.status in ('closed', 'Completed', 'inactive')
)
select
  i.owner_name,
  i.owner_phone,
  i.contact_name,
  i.contact_phone,
  count(*) as spans_attributed_to_closed
from bad b
join public.interactions i on i.interaction_id = b.interaction_id
group by 1, 2, 3, 4
order by spans_attributed_to_closed desc nulls last
limit 30;

