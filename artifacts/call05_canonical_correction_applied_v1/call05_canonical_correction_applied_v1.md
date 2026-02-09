# call05_canonical_correction_applied_v1

Generated UTC: 2026-02-08T21:59:40Z
Interaction: `a984779b-44ad-4772-b19e-7b2e844f1777` / `cll_06E0P6KYB5V7S5VYQA8ZTRQM4W`

## Canonical Correction Applied

Target project (adjudicated):
- `47cb7720-9495-4187-8220-a8100c3b67aa` (`Moss Residence`)

### Before (captured immediately pre-patch)
- project_id: `4d5a7252-f3bb-4e31-80fc-e72a7ec78520` (`White Residence`)
- owner_name: `Kaylen Hurley`
- contact_name: `Zack Sittler`
- needs_review: `false`
- project_attribution_confidence: `null`
- review_reasons: `["router_call_failed"]`

### After (live row after PATCH)

```json
{
  "interaction_id": "cll_06E0P6KYB5V7S5VYQA8ZTRQM4W",
  "project_id": "47cb7720-9495-4187-8220-a8100c3b67aa",
  "owner_name": "Kaylen Hurley",
  "contact_name": "Zack Sittler",
  "needs_review": false,
  "project_attribution_confidence": 0.67,
  "review_reasons": [
    "manual_canonical_correction",
    "call05_reattribution_bruteforce_data1_v1"
  ],
  "event_at_utc": "2026-01-29T18:53:31+00:00"
}
```

## Downstream Conflict Checks

1. `review_queue` historical resolution notes still reference old project id.
- conflict_count: `1`
- details: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/review_queue_rows.json`

2. Active `span_attributions` with non-null `applied_project_id` that differs from canonical target.
- conflict_count: `0`
- details: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/active_span_attributions.json`

3. Active span inventory snapshot.
- source: `/Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/active_spans.json`

## Rollback Note

If rollback is required, PATCH `interactions` where `interaction_id=cll_06E0P6KYB5V7S5VYQA8ZTRQM4W` to restore:
- `project_id=4d5a7252-f3bb-4e31-80fc-e72a7ec78520`
- `review_reasons=["router_call_failed"]`
- `project_attribution_confidence=null`

## Operational Note

This correction updates canonical `interactions.project_id` for coordinator-facing state. Historical `review_queue` rows remain immutable evidence and may continue to reference the prior auto-resolution path.
