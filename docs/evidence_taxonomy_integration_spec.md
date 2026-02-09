# Evidence Taxonomy — AI-Router Integration Spec

**Author:** DATA-8 | **Thread:** evidence | **Version:** v1.0
**For:** DEV-7 (pipeline integration)
**Date:** 2026-02-09

---

## 1. Overview

The `evidence_types` table provides a 5-tier vocabulary for classifying attribution
evidence. Per CHAD directive (AI-Forward Posture): this is vocabulary for the LLM,
NOT a rule engine. The model classifies each anchor into a tier and uses that
classification as context for its own confidence assessment. No hardcoded ceilings
or gates.

**Mantra:** Compute the signal. Classify the tier. Feed it to the model. Let the model judge.

---

## 2. Schema Changes

### 2a. New table: `evidence_types`
```sql
evidence_types (
  id TEXT PRIMARY KEY,          -- e.g., 'exact_project_name', 'county_or_city'
  tier INTEGER NOT NULL,        -- 1=smoking_gun, 2=strong, 3=contextual, 4=weak, 5=anti_signal
  tier_label TEXT NOT NULL,     -- human-readable tier name
  typical_strength TEXT NOT NULL, -- descriptive guidance for the LLM
  ambiguity_notes TEXT,         -- when this evidence type can be misleading
  example TEXT,                 -- concrete example from HCB context
  description TEXT              -- full description
)
```

22 evidence types across 5 tiers. See production table for full data.

### 2b. New columns on `span_attributions`
```sql
evidence_tier INTEGER          -- best (lowest number = strongest) tier observed
evidence_classification JSONB  -- per-anchor detail, see format below
```

---

## 3. Tier Definitions

| Tier | Label | Meaning | Examples |
|------|-------|---------|----------|
| 1 | smoking_gun | Deterministic, one-to-one mapping | exact_project_name, street_address, lot_subdivision, unique_moniker, parcel_id |
| 2 | strong | High confidence, low ambiguity | unique_client_name, unique_alias, address_fragment_plus_corroboration, client_entity_match |
| 3 | contextual | Useful but ambiguous alone | contact_low_fanout, trade_plus_phase, geo_proximity, continuity_callback, mentioned_contact_unique |
| 4 | weak | Noise without corroboration | county_or_city, contact_high_fanout, phonetic_near_match, first_name_only, zip_code |
| 5 | anti_signal | Should REDUCE confidence | hcb_staff_name, floater_contact, generic_trade_no_context |

---

## 4. AI-Router Integration (DEV-7 Implementation Guide)

### 4a. Pre-LLM: Classify anchors

Before sending the attribution prompt, context-assembly or ai-router should classify
each anchor/matched term against the `evidence_types` table:

```typescript
// Pseudocode: classify each anchor
const classifiedAnchors = anchors.map(anchor => {
  const evidenceType = evidenceTypes.find(et => et.id === anchor.match_type);
  return {
    ...anchor,
    evidence_type_id: evidenceType?.id ?? 'other',
    tier: evidenceType?.tier ?? 3,
    tier_label: evidenceType?.tier_label ?? 'contextual',
    typical_strength: evidenceType?.typical_strength ?? 'Unknown',
    ambiguity_notes: evidenceType?.ambiguity_notes ?? null,
  };
});
```

For match types not in the evidence_types table (e.g., `db_scan`, `other`), default
to tier 3 (contextual) and flag for future taxonomy expansion.

### 4b. Inject tier context into the LLM prompt

Add a new section to the attribution prompt between the candidates and the output
format instruction:

```
## EVIDENCE STRENGTH TAXONOMY
Each anchor below has been pre-classified into an evidence tier. Use these
classifications as context — they represent typical strength in construction
attribution, but YOU determine how much weight each piece of evidence deserves
in this specific context.

Tier 1 (smoking_gun): Usually deterministic, one-to-one mapping to a project.
Tier 2 (strong): Usually high confidence with low ambiguity.
Tier 3 (contextual): Useful context but ambiguous when standing alone.
Tier 4 (weak): Typically noise without corroboration from stronger signals.
Tier 5 (anti_signal): Evidence that should typically REDUCE confidence in
  a specific project match. Staff names, floater contacts, and generic trades
  are diagnostic of who is SPEAKING, not which project is being discussed.

The classified anchors for this span:
${JSON.stringify(classifiedAnchors, null, 2)}

IMPORTANT: These tiers are guidelines, not rules. A Tier 4 signal with strong
contextual corroboration may warrant higher confidence than its tier suggests.
A Tier 1 signal can be wrong if the transcript is ambiguous. Use your judgment.
```

### 4c. Amend the output format

Add `evidence_classification` to the JSON output schema the model returns:

```json
{
  "project_id": "<uuid or null>",
  "confidence": 0.00-1.00,
  "decision": "assign|review|none",
  "reasoning": "<1-3 sentences>",
  "anchors": [{
    "text": "<matched term>",
    "candidate_project_id": "<uuid>",
    "match_type": "<current match_type>",
    "evidence_type_id": "<from evidence_types table>",
    "tier": 1-5,
    "tier_label": "<tier name>",
    "quote": "<EXACT quote, max 50 chars>"
  }],
  "best_evidence_tier": 1-5,
  "suggested_aliases": [...]
}
```

### 4d. Post-LLM: Write classification to span_attributions

After receiving the model response, write the classification data:

```typescript
await db.from('span_attributions').update({
  evidence_tier: response.best_evidence_tier,
  evidence_classification: response.anchors.map(a => ({
    anchor_text: a.text,
    evidence_type_id: a.evidence_type_id,
    tier: a.tier,
    tier_label: a.tier_label,
  })),
}).eq('id', attributionId);
```

### 4e. What NOT to do

- **DO NOT** add `base_weight` columns or multiply weights by tier
- **DO NOT** implement confidence ceilings (e.g., "tier 4 caps at 0.35")
- **DO NOT** block auto-assign based on tier alone
- **DO NOT** override the model's confidence with tier-based arithmetic
- **DO** present tier classifications as context for the model's judgment
- **DO** let the model explain why it trusts weak evidence in specific contexts

---

## 5. Existing Guardrails — Relationship to Taxonomy

The ai-router already has guardrails (hard anchor cap, affinity gap, weak signal
penalties). These should be REVIEWED in light of this taxonomy:

- **Hard anchor cap** (no strong anchor → cap confidence to 0.60): This is a
  heuristic that approximates "no Tier 1-2 evidence." Consider replacing with
  injecting the tier classification and letting the model self-regulate.
- **Weak signal penalties** (-0.08 per weak signal): This is arithmetic the model
  should be doing. Present the weakness as context, don't subtract from its score.

These changes are suggestions for a future iteration. For now, the taxonomy
injection is additive and doesn't need to remove existing guardrails.

---

## 6. Testing: Call 05 Case Study

Call 05 (`cll_06E0P6KYB5V7S5VYQA8ZTRQM4W`) was misattributed to Moss Residence.

### Span 2 attribution evidence:
- **Anchor:** "Oconee County" → match_type: `city_or_location`
- **Evidence type:** `county_or_city` → **Tier 4 (weak)**
- **Why it failed:** Oconee County contains 5 active HCB projects. The county name
  alone cannot distinguish between them. The model assigned 0.75 confidence based on
  a single Tier 4 signal — under the taxonomy, this would be flagged as atypical
  (Tier 4 signals are described as "noise without corroboration").

### Expected behavior with taxonomy:
The model would see:
```
Anchor: "Oconee County" → evidence_type: county_or_city, tier: 4 (weak)
Typical strength: "Low confidence — counties/cities typically contain multiple HCB projects"
Ambiguity notes: "Oconee County has 5 active projects; Morgan County has 7."
```
With this context, the model should self-correct to a lower confidence and
decision=review, because it now understands that county-only evidence is typically
insufficient for construction project attribution.

---

## 7. Migration Proof

- Table: `evidence_types` — 22 rows, 5 tiers
- Columns added: `span_attributions.evidence_tier`, `span_attributions.evidence_classification`
- RLS: enabled, public read, service_role manage
- Migration name: `create_evidence_types_reference_table`
