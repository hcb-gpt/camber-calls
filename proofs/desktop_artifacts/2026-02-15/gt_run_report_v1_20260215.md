# GT Run Report v1 (template)

## 0) Metadata
- `run_id`: 
- `run_started_at_utc`: 
- `run_completed_at_utc`: 
- `runner_version`:
- `runner_commit_sha`:
- `pipeline_version_before`:
- `pipeline_version_after`:
- `edge_deploy_refs` (if applicable): ai-router=, context-assembly=, segmenter=, journal-extract=
- `db_ref`: Supabase `rjhdwidddtfetbwqolof`

## 1) Inputs
- `gt_manifest_path`: `/Users/chadbarlow/Desktop/gt_smoke_batch_v1_20260215.csv` (or full)
- `rows_total`:
- `interaction_ids_unique`:
- `spans_with_span_id`:
- Evidence packs referenced:
  - `/Users/chadbarlow/Desktop/anchor_catalog_v1_20260215.csv`
  - `/Users/chadbarlow/gh/hcb-gpt/camber-calls/proofs/gt/inputs/2026-02-15/homeowner_override_proofset_20260215.csv`

## 2) Execution
- Command(s):
  - 
- Rerun selection rules (if any beyond manifest):
  - 
- Concurrency / rate limits:
  - 

## 3) Headline metrics
### 3.1 Attribution correctness
- `overall_accuracy` = correct / total
- `project_accuracy_excl_gt_none` = correct / (total - gt_none)
- `review_rate` = predicted_review / total
- `none_rate` = predicted_none / total
- `staff_leak_rate` = predicted_project in {Sittler…} / total  (should be 0 after P0)

### 3.2 Bucket metrics (tag-stratified)
For each bucket tag in the manifest, report:
- rows, accuracy, review_rate, none_rate

Buckets to always include:
- `bucket:homeowner_override`
- `bucket:staff_leak`
- `bucket:vendor_binding`
- `bucket:location_anchor` (and `anchor:*` sub-tags)
- `bucket:materials_spec`
- `bucket:colloquial`
- `bucket:multi_project`

### 3.3 Deltas vs baseline
- `baseline_run_id`:
- `accuracy_delta_pp`:
- `review_rate_delta_pp`:
- Bucket deltas: 

## 4) Failures (top N)
Include at least:
- interaction_id, span_id (or span_index), expected_project_id, predicted_project_id, predicted_decision/confidence, notes

## 5) Review contamination (metric v1)
Source: `/Users/chadbarlow/Desktop/review_contamination_metric_v1_20260215.md`

### 5.1 Definitions (exact)
- `latest_attr(span_id)`: most recent `public.span_attributions` row by `attributed_at DESC` (tie-breaker `id DESC`).
- **reviewish span** iff:
  - `latest_attr.decision IN ('review','none')` OR
  - `latest_attr.applied_project_id IS NULL`

### 5.2 Tier J0 (staging contamination) — primary scorecard metric
**Forbidden write (J0):** any **active** `public.journal_claims` row with `source_span_id = span_id` for a reviewish span.

For a window `[since, now]`:
- `review_span_count`: spans whose latest attribution is reviewish AND `latest_attr.attributed_at >= since`
- `review_contamination_count`: number of those spans with ≥1 active `journal_claims` row where `journal_claims.created_at >= since`
- `contamination_rate` = `review_contamination_count / review_span_count`

Secondary diagnostics:
- `review_contamination_claim_row_count`: active `journal_claims` rows created in-window on reviewish spans
- `review_contamination_embedded_claim_row_count`: same but `embedding IS NOT NULL`

### 5.3 Tier J1 (ledger contamination) — optional
**Forbidden write (J1):** any `public.belief_claims` row whose `journal_claim_id` points to a `journal_claims` row sourced from a reviewish span.

### 5.4 Poisoning invariant (must be 0)
Even if J0 exists, reuse gates can prevent poisoning.

**Invariant:** `journal_claims.claim_confirmation_state = 'confirmed'` must never occur for claims sourced from reviewish spans.

### 5.5 SQL snippets (read-only)

**A) Current state snapshot (all time): J0 contamination**
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

**B) Windowed scorecard metric (default: last 7 days): J0 contamination**
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

**C) Batch detection template (interaction_ids): list contaminated spans**
(Replace the interaction_id list.)
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

**F) Poisoning invariant check (should be 0): confirmed claims on reviewish spans**
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

### 5.6 Report values for this run
- Window used for contamination: `since = run_started_at_utc` (recommended) or last 7d.
- `review_span_count`:
- `review_contamination_count`:
- `contamination_rate`:
- `review_contamination_claim_row_count`:
- `review_contamination_embedded_claim_row_count`:
- `belief_contamination_count_7d` (optional):
- `confirmed_claim_rows_on_reviewish` (must be 0):

## 6) Integration proposal (runner output)
Minimal change to GT batch runner (DEV-owned):
- Record `run_started_at_utc` and include it in artifacts.
- After the run, execute the batch contamination query (C) restricted to spans in the batch, plus a `journal_claims.created_at >= run_started_at_utc` filter.
- Emit in `results.csv` (or summary):
  - `is_reviewish` (latest decision review/none OR applied_project_id null)
  - `journal_claim_rows_since_run_start`
  - `journal_claim_embedded_rows_since_run_start`
- Emit in `summary.md`:
  - `review_contamination_count`, `contamination_rate`, `confirmed_claim_rows_on_reviewish`.

Suggested pass/fail policy (until write-gate ships):
- **FAIL** only if poisoning invariant breaks (`confirmed_claim_rows_on_reviewish > 0`).
- Track J0/J1 contamination as trend metrics; do not fail-run on non-zero J0 until gate is implemented.

## 7) Artifacts
- `run_dir`: `/Users/chadbarlow/Desktop/gt_batch_runs/<ts>/`
- Files:
  - `results.csv`
  - `failures.csv`
  - `summary.md`
  - `contamination.csv` (optional)

## 8) Next actions
- 
