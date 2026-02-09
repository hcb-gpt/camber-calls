# call05_canonical_correction_applied_v1 (clean proof report)

Generated UTC: 2026-02-08T22:08:19Z

## Interaction
- interaction_id:   cll_06E0P6KYB5V7S5VYQA8ZTRQM4W
- canonical project_id target: 47cb7720-9495-4187-8220-a8100c3b67aa (Moss Residence)

## Before (captured pre-patch snapshot from original execution artifact)
- project_id: 4d5a7252-f3bb-4e31-80fc-e72a7ec78520 (White Residence)
- owner_name: Kaylen Hurley
- review_reasons: ["router_call_failed"]
- source: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/call05_canonical_correction_applied_v1.md

## After (live verification via Supabase REST)
- source JSON: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/live_after_interaction_20260208.json
- sha256: 1ed8bf8d0cea35580806146464c7bac96e70b7bb1af43a6d20520c10900b7cc2
- verified row payload:


en
[{"interaction_id":"cll_06E0P6KYB5V7S5VYQA8ZTRQM4W","project_id":"47cb7720-9495-4187-8220-a8100c3b67aa","owner_name":"Kaylen Hurley","contact_name":"Zack Sittler","needs_review":false,"project_attribution_confidence":0.67,"review_reasons":["manual_canonical_correction","call05_reattribution_bruteforce_data1_v1"],"event_at_utc":"2026-01-29T18:53:31+00:00","ingested_at_utc":"2026-01-29T19:10:14.672883+00:00"}]

## Resolver/timestamp evidence
- review_reasons includes: ["manual_canonical_correction", "call05_reattribution_bruteforce_data1_v1"]
- event_at_utc: 2026-01-29T18:53:31+00:00
- ingested_at_utc: 2026-01-29T19:10:14.672883+00:00
- review_queue historical resolution actor: auto_resolve_bulk_cleanup
- review_queue evidence file: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/live_review_queue_20260208.json
- review_queue sha256: 09e4654ee539fddac5e8602699ddd2ea90bc7666a7a521ce901c47e9f3e2bbed

## Conflict checks
1. Active span_attributions with non-null applied_project_id not matching canonical target:
- mismatch_count: 0
- evidence file: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/live_span_attributions_20260208.json
- sha256: fbe7136f66a177ee5e8d6d2b4dc8c03e269e28383a472830873329ef638c4084

2. Historical review_queue notes still referencing old project_id (expected legacy evidence):
- legacy_reference_count: 1
- evidence file: /Users/chadbarlow/gh/hcb-gpt/camber-calls/artifacts/call05_canonical_correction_applied_v1/live_review_queue_20260208.json

## Rollback note
If rollback is needed, patch interactions.project_id for cll_06E0P6KYB5V7S5VYQA8ZTRQM4W back to 4d5a7252-f3bb-4e31-80fc-e72a7ec78520 and restore prior review_reasons.

