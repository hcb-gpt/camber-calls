# Review Contamination Metric v1 (2026-02-15)

## Goal
Detect and quantify **durable evidence writes** that occur even when a span’s **latest attribution decision is `review`/`none`** (or the attribution was never applied). These writes are considered “review contamination” because they can accumulate as reusable evidence and (depending on downstream gates) influence future attribution.

This doc defines:
- A precise contamination definition
- A scorecard-ready metric (`review_contamination_count`, `contamination_rate`)
- Read-only SQL queries to detect + sample contamination
- (Optional) minimal DEV gate proposals to prevent it

---

## Definitions (v1)

### Latest attribution per span
`latest_attr(span_id)` = the most recent row in `public.span_attributions` for that `span_id`, ordered by `attributed_at DESC` (tie-breaker: `id DESC`).

### Reviewish span
A span is **reviewish** if:
- `latest_attr.decision IN ('review','none')` **OR**
- `latest_attr.applied_project_id IS NULL`

Rationale: `applied_project_id` is the only “this was applied” indicator; anything else should not produce reusable evidence.

---

## What is “contamination”?

### Tier J0 (staging contamination) — primary metric
**Forbidden write:** any **active** `public.journal_claims` row with `source_span_id = span_id` for a reviewish span.

This is the simplest invariant to enforce and measure.

### Tier J1 (ledger contamination) — optional but recommended
**Forbidden write:** any `public.belief_claims` row whose `journal_claim_id` points to a `public.journal_claims` row sourced from a reviewish span.

This matters if/when the belief ledger is used as reusable project state.

### Poisoning check (should be 0)
Even if J0 writes exist, **future attribution should not be influenced** if reuse gates enforce confirmation.

**Poisoning invariant:** `claim_confirmation_state = 'confirmed'` must never occur on `journal_claims` sourced from reviewish spans.

---

## Scorecard metric definitions

For a time window `[since, now]`:

- `review_span_count` := number of spans whose latest attribution is reviewish **and** `latest_attr.attributed_at >= since`
- `review_contamination_count` := number of those spans with **≥1** active `journal_claims` row where `journal_claims.created_at >= since`
- `contamination_rate` := `review_contamination_count / review_span_count`

Secondary (useful diagnostics):
- `review_contamination_claim_row_count` := number of active `journal_claims` rows created in-window on reviewish spans
- `review_contamination_embedded_claim_row_count` := number of those rows with `embedding IS NOT NULL`
- `belief_contamination_count` := `belief_claims` rows created in-window that originate from reviewish spans (J1)

---

## SQL (read-only)

### A) Current state snapshot (all time): J0 contamination
```sql
with latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, project_id as predicted_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
),
reviewish as (
  select span_id
  from latest_attr
  where decision in ('review','none') or applied_project_id is null
),
claims as (
  select
    source_span_id as span_id,
    count(*) as claim_rows,
    count(*) filter (where embedding is not null) as embedded_claim_rows
  from journal_claims
  where active is true and source_span_id is not null
  group by source_span_id
)
select
  (select count(*) from reviewish) as reviewish_spans_total,
  count(*) filter (where c.claim_rows is not null) as contaminated_spans_total,
  round(
    count(*) filter (where c.claim_rows is not null)::numeric
    / nullif((select count(*) from reviewish), 0),
    4
  ) as contamination_rate_total,
  coalesce(sum(c.claim_rows), 0) as claim_rows_on_reviewish_spans,
  coalesce(sum(c.embedded_claim_rows), 0) as embedded_claim_rows_on_reviewish_spans
from reviewish r
left join claims c on c.span_id = r.span_id;
```

### B) Windowed scorecard metric (default: last 7 days): J0 contamination
```sql
with latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
),
review_spans as (
  select span_id
  from latest_attr
  where (decision in ('review','none') or applied_project_id is null)
    and attributed_at >= now() - interval '7 days'
),
claims_recent as (
  select
    source_span_id as span_id,
    count(*) as claim_rows,
    count(*) filter (where embedding is not null) as embedded_claim_rows
  from journal_claims
  where active is true
    and source_span_id is not null
    and created_at >= now() - interval '7 days'
  group by source_span_id
)
select
  (select count(*) from review_spans) as review_spans_7d,
  count(*) filter (where cr.claim_rows is not null) as review_contamination_count,
  round(
    count(*) filter (where cr.claim_rows is not null)::numeric
    / nullif((select count(*) from review_spans), 0),
    4
  ) as contamination_rate,
  coalesce(sum(cr.claim_rows), 0) as review_contamination_claim_row_count,
  coalesce(sum(cr.embedded_claim_rows), 0) as review_contamination_embedded_claim_row_count
from review_spans rs
left join claims_recent cr on cr.span_id = rs.span_id;
```

### C) Batch detection template (interaction_ids): list contaminated spans
Replace the `interaction_id` list.
```sql
with target_spans as (
  select cs.id as span_id, cs.interaction_id, cs.span_index
  from conversation_spans cs
  where cs.interaction_id in (
    'cll_REPLACE_ME_1',
    'cll_REPLACE_ME_2'
  )
),
latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
),
claim_counts as (
  select
    source_span_id as span_id,
    count(*) as claim_rows,
    count(*) filter (where embedding is not null) as embedded_claim_rows,
    max(created_at) as last_claim_created_at
  from journal_claims
  where active is true and source_span_id is not null
  group by source_span_id
)
select
  ts.interaction_id,
  ts.span_index,
  la.decision,
  la.applied_project_id,
  la.attributed_at as latest_attributed_at,
  cc.claim_rows,
  cc.embedded_claim_rows,
  cc.last_claim_created_at
from target_spans ts
left join latest_attr la on la.span_id = ts.span_id
left join claim_counts cc on cc.span_id = ts.span_id
where (la.decision in ('review','none') or la.applied_project_id is null)
  and cc.claim_rows is not null
order by ts.interaction_id, ts.span_index;
```

### D) Top contamination examples (last 7 days): 3 most recent contaminated spans
```sql
with latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
),
contaminated_spans as (
  select
    jc.source_span_id as span_id,
    cs.interaction_id,
    cs.span_index,
    max(jc.created_at) as last_claim_created_at,
    count(*) as claim_rows,
    count(*) filter (where jc.embedding is not null) as embedded_claim_rows,
    la.decision as latest_decision,
    la.applied_project_id
  from journal_claims jc
  join latest_attr la on la.span_id = jc.source_span_id
  join conversation_spans cs on cs.id = jc.source_span_id
  where jc.active is true
    and jc.source_span_id is not null
    and jc.created_at >= now() - interval '7 days'
    and (la.decision in ('review','none') or la.applied_project_id is null)
  group by jc.source_span_id, cs.interaction_id, cs.span_index, la.decision, la.applied_project_id
),
top_spans as (
  select *
  from contaminated_spans
  order by last_claim_created_at desc
  limit 3
)
select
  t.*,
  left(jc.claim_text, 160) as example_claim_text_160,
  jc.claim_type as example_claim_type
from top_spans t
join lateral (
  select claim_text, claim_type
  from journal_claims
  where source_span_id = t.span_id and active is true
  order by created_at desc
  limit 1
) jc on true
order by t.last_claim_created_at desc;
```

### E) J1 (belief ledger) contamination: belief_claims sourced from reviewish spans
```sql
with latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
),
reviewish_jc as (
  select jc.id as journal_claim_id
  from journal_claims jc
  join latest_attr la on la.span_id = jc.source_span_id
  where jc.active is true
    and jc.source_span_id is not null
    and (la.decision in ('review','none') or la.applied_project_id is null)
)
select
  count(*) as belief_contamination_count_total,
  count(*) filter (where bc.created_at >= now() - interval '7 days') as belief_contamination_count_7d,
  count(distinct bc.source_run_id) as distinct_source_runs
from belief_claims bc
join reviewish_jc rj on rj.journal_claim_id = bc.journal_claim_id;
```

### F) Poisoning invariant check (should be 0): confirmed claims on reviewish spans
```sql
with latest_attr as (
  select distinct on (span_id)
    span_id, decision, applied_project_id, attributed_at
  from span_attributions
  order by span_id, attributed_at desc nulls last, id desc
)
select count(*) as confirmed_claim_rows_on_reviewish
from journal_claims jc
join latest_attr la on la.span_id = jc.source_span_id
where jc.active is true
  and jc.source_span_id is not null
  and (la.decision in ('review','none') or la.applied_project_id is null)
  and jc.claim_confirmation_state = 'confirmed';
```

---

## Current snapshot (as of 2026-02-15 22:12 UTC)

From live DB queries:

**J0 (all time)**
- `reviewish_spans_total = 1896`
- `contaminated_spans_total = 651` → `contamination_rate_total = 0.3434`
- `claim_rows_on_reviewish_spans = 3444`
- `embedded_claim_rows_on_reviewish_spans = 459`

**J0 (last 7 days)**
- `review_spans_7d = 1788`
- `review_contamination_count = 591` → `contamination_rate = 0.3305`
- `review_contamination_claim_row_count = 3083`
- `review_contamination_embedded_claim_row_count = 218`

**J1 (belief ledger)**
- `belief_contamination_count_total = 180` (also `= 180` in last 7d)
- `distinct_source_runs = 39`

**Poisoning check**
- `confirmed_claim_rows_on_reviewish = 0`

---

## Optional minimal gates (DEV-implementable)

1) **Write gate in `journal-extract`**: only write `journal_claims` when `decision='assign'` **and** `applied_project_id IS NOT NULL` (no fallback to predicted `project_id` for durable writes).
2) **Promotion gate in `promote_journal_claims_to_belief`**: only promote `journal_claims` where `claim_confirmation_state='confirmed'` (prevents J1 contamination even if J0 rows exist).
3) **(Defense-in-depth) Retrieval gates**: ensure any retrieval paths over `journal_claims` filter `claim_confirmation_state='confirmed'` (already true for `xref_search_journal_claims` in DB and for `context-assembly` claim queries).

