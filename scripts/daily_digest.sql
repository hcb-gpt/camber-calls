-- daily_digest.sql
-- STRAT TURN 72: GPT-DEV-6 daily digest (ops without dashboards)
--
-- SQL-only daily digest producing:
--   - total calls processed
--   - % PASS
--   - avg review items/call
--   - review_gap count
--   - reseed churn (override_reseeds/call)
--
-- Usage:
--   psql "$DATABASE_URL" -v day_start='2026-01-31 00:00:00+00' -v day_end='2026-02-01 00:00:00+00' -f scripts/daily_digest.sql
--
-- Note: Uses core tables directly (no snapshot table required)

\echo '=== DAILY DIGEST ==='

with
params as (
  select
    :'day_start'::timestamptz as day_start,
    :'day_end'::timestamptz as day_end
),

-- All interactions touched in the day
calls as (
  select distinct interaction_id
  from conversation_spans cs, params p
  where cs.created_at >= p.day_start
    and cs.created_at <  p.day_end
),

-- Active spans per interaction
active_spans as (
  select
    cs.interaction_id,
    count(*) as spans_active
  from conversation_spans cs, params p
  where cs.is_superseded = false
    and cs.created_at >= p.day_start
    and cs.created_at <  p.day_end
  group by 1
),

-- Review queue items for active spans
review_items as (
  select
    cs.interaction_id,
    count(rq.*) as review_items
  from conversation_spans cs
  left join review_queue rq on rq.span_id = cs.id
  cross join params p
  where cs.is_superseded = false
    and cs.created_at >= p.day_start
    and cs.created_at <  p.day_end
  group by 1
),

-- Gap: needs_review=true but no review_queue row
review_gap as (
  select
    cs.interaction_id,
    count(*) as review_gap
  from conversation_spans cs
  join span_attributions sa on sa.span_id = cs.id
  left join review_queue rq on rq.span_id = cs.id
  cross join params p
  where cs.is_superseded = false
    and (sa.needs_review = true or sa.decision = 'review')
    and rq.span_id is null
    and cs.created_at >= p.day_start
    and cs.created_at <  p.day_end
  group by 1
),

-- Reseed count per interaction
reseeds as (
  select
    ol.interaction_id,
    count(*) as reseed_count
  from override_log ol
  cross join params p
  where ol.entity_type = 'reseed'
    and ol.created_at >= p.day_start
    and ol.created_at <  p.day_end
  group by 1
),

-- Score each interaction
scored as (
  select
    c.interaction_id,
    coalesce(a.spans_active, 0) as spans_active,
    coalesce(ri.review_items, 0) as review_items,
    coalesce(rg.review_gap, 0) as review_gap,
    coalesce(r.reseed_count, 0) as reseed_count,
    case
      when coalesce(rg.review_gap, 0) = 0 and coalesce(a.spans_active, 0) > 0 then 1
      else 0
    end as is_pass
  from calls c
  left join active_spans a on a.interaction_id = c.interaction_id
  left join review_items ri on ri.interaction_id = c.interaction_id
  left join review_gap rg on rg.interaction_id = c.interaction_id
  left join reseeds r on r.interaction_id = c.interaction_id
)

select
  (select date_trunc('day', day_start) from params) as day,
  count(*) as total_calls_processed,
  sum(is_pass) as pass_calls,
  case when count(*) = 0 then 0
       else round(100.0 * sum(is_pass)::numeric / count(*), 2)
  end as pass_pct,
  case when count(*) = 0 then 0
       else round(avg(review_items)::numeric, 3)
  end as avg_review_items_per_call,
  sum(review_gap) as review_gap_count,
  case when count(*) = 0 then 0
       else round(avg(reseed_count)::numeric, 3)
  end as reseed_churn_per_call,
  sum(spans_active) as total_spans_active
from scored;
