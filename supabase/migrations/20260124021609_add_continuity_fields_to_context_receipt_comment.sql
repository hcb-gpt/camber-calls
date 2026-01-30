comment on column public.interactions.context_receipt is $$Receipt anchor: what context was assembled, what was truncated.

Continuity contract extension (2026-01-24):
- continuity_candidate_calls: ["cll_xxx", ...]
- continuity_evidence_spans_current: [{start,end,text}, ...]
- continuity_link_target_call_id: "cll_xxx" | null
- continuity_link_target_spans_prior: [{start,end,text}, ...]
- candidate_sources_split: { transcript_grounded: [...], proxy_history: [...] }
- continuity_tier: "TIER_1" | "TIER_2" | "TIER_3" | null
- gap_hours: number | null
- floater_involved: boolean | null

(See TRAM memo: to_dev27_from_strata23_2026-01-24_0200Z_continuity_receipt_schema.md)$$;;
