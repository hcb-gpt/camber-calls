# Identity Matching Merge Gate Spec v1.0-DRAFT

> Reconstructed by DEV-1 from TRAM receipts + live codebase.
> Original authored by DATA (receipt: `identity_merge_gate_spec_v1_ready`).
> STRAT-approved defaults (receipt: `ack_identity_merge_gates_spec_v1_delivery`).

## 1. Purpose

Define the rules governing when two identity records (contacts, speakers, aliases)
may be automatically merged, flagged for human review, or rejected. The goal is
**zero false merges** while maximizing automated resolution of true matches.

## 2. Merge Gate Rules

### 2.1 Core Principle

**Name-only matches NEVER auto-merge.** A corroborating anchor is always required.

### 2.2 Anchors (Corroborating Evidence)

An anchor is an independent signal that two records refer to the same entity:

| Anchor Type | Confidence | Example |
|-------------|-----------|---------|
| Phone (E.164 match) | 0.95 | Same phone on both records |
| Email (exact match) | 0.95 | Same email domain+local |
| Address (fuzzy match) | 0.85 | Same street address |
| Company/Domain | 0.80 | Same organization |
| Project assignment | 0.90 | Both assigned to same project |

### 2.3 Decision Matrix

| Name Match | Anchor Present | Conflicts | Decision |
|-----------|---------------|-----------|----------|
| Exact | Yes | None | **AUTO_MERGE** |
| Phonetic (strong) | Yes | None | **AUTO_MERGE** |
| Phonetic (strong) | No | None | **SUGGEST** (human review) |
| Phonetic (weak) | Yes | None | **SUGGEST** (human review) |
| Phonetic (weak) | No | Any | **REJECT** |
| Name-only | Any | Any | **SUGGEST** at best |
| Any | Any | Conflict detected | **BLOCK** |

### 2.4 Conflict Detection

A conflict exists when:
- Two records have the same name but different phones/emails
- Records are assigned to different, non-overlapping projects
- Contact types conflict (e.g., one is `internal`, the other `client`)

## 3. Short-Token Policy

### 3.1 Rule

Tokens of **3 characters or fewer** are excluded from phonetic matching unless
they appear in the curated nickname whitelist.

Rationale: Short tokens produce excessive false positives in Double Metaphone
(e.g., "Bo", "Al", "Ed" all produce similar codes).

### 3.2 Nickname Whitelist

Curated exceptions — short tokens that are legitimate names and should be
matched phonetically:

```
Bob -> Robert
Jim -> James
Joe -> Joseph
Dan -> Daniel
Ben -> Benjamin
Tom -> Thomas
Tim -> Timothy
Sam -> Samuel
Pat -> Patrick/Patricia
Ray -> Raymond
Roy -> Roy
Lee -> Lee
Liz -> Elizabeth
Ann -> Anne/Anna
Sue -> Susan
Deb -> Deborah
Rob -> Robert
Ted -> Theodore
Hal -> Harold
Kat -> Katherine
Max -> Maxwell
Rex -> Rex
Dot -> Dorothy
Fay -> Faye
Gay -> Gay
Gus -> Augustus
Bud -> Buddy
Art -> Arthur
```

### 3.3 Additions Needed (from DATA eval)

The following mappings were identified as gaps during the 100-pair eval:

| Short Form | Full Form | Source |
|-----------|----------|--------|
| Debbie | Deborah | eval_pairs_supplement_100_pair_complete |
| Randy | Randall | eval_pairs_supplement_100_pair_complete |
| Mitch | Mitchell | eval_pairs_supplement_100_pair_complete |

These should be added to the contact aliases for the relevant contacts.

## 4. Candidate Gating (Phonetic-Adjacent-Only)

### 4.1 Algorithm

The system uses **Double Metaphone** for phonetic encoding. This is already
implemented in the PostgreSQL functions patched in PR#31.

### 4.2 Current Implementation (v1.0 — Levenshtein on raw strings)

As implemented in `find_fuzzy_alias_matches`:
- Trigram similarity (pg_trgm)
- Levenshtein distance with `LENGTH > 3` gate
- Soundex comparison
- Double Metaphone comparison

### 4.3 Recommended Upgrade (v1.1 — Jaro-Winkler on phonetic codes)

Apply Jaro-Winkler similarity to Double Metaphone codes rather than raw strings:

| Code Length | Threshold | Action |
|------------|----------|--------|
| >= 5 chars | JW >= 0.85 | MATCH candidate |
| 4 chars | JW >= 0.90 | MATCH candidate (stricter) |
| <= 3 chars | REJECT | Too ambiguous |

### 4.4 Match Strength Classification

Implemented in `classifyMatchStrength()` (process-call + context-assembly):

| Classification | Criteria | Auto-merge eligible? |
|---------------|---------|---------------------|
| **strong** | Exact project name, multi-word alias, last-name match, location, or single-word >= 6 chars | Yes (with anchor) |
| **weak** | Single short first-name-only token, no corroboration | No — stays POSSIBLE |

**Rule:** First-name-only phonetic match = "possible" only, never auto-merge.

Candidates with only weak evidence get:
- Capped confidence (max 0.35)
- `weak_only: true` flag
- Lower rank score (10 pts per match vs 20 for strong)

## 5. Acceptance Test Suite

See `tests/identity/eval_pairs.json` for the full fixture.

### 5.1 Test Categories

| Category | Count | Description |
|---------|-------|-------------|
| Name Pairs (NP) | 30 | Phonetic match, whitelist, short-token, exact, edge cases |
| Anchor Integration (AI) | 12 | Auto-merge, candidate, blocked, conflict scenarios |
| CAMBER Edge Cases (CE) | 5 | Transcript matching, unknown placeholders, role conflicts |

### 5.2 Key Test Cases

- **NP-01**: Bob Smith / Robert Smith → MATCH (nickname whitelist)
- **NP-02**: Bo Hurley / Joseph Hurley → MATCH (known alias)
- **NP-03**: Brian Dove / Brian Young → REJECT (different last names)
- **AI-01**: Same name + same phone → AUTO_MERGE
- **AI-02**: Same name + no anchor → SUGGEST
- **CE-01**: "Unknown Caller" / "Unknown" → REJECT (placeholder)

## 6. Eval Set Design

Target: **100 pairs** across 7 categories.

| Category | Target Count | Purpose |
|---------|-------------|---------|
| True positive (exact) | 15 | Baseline |
| True positive (phonetic) | 20 | Phonetic accuracy |
| True negative (different people) | 20 | False positive prevention |
| Nickname/alias | 15 | Whitelist coverage |
| Short-token edge cases | 10 | Short-token policy validation |
| Anchor integration | 10 | Merge gate logic |
| CAMBER-specific | 10 | Real-world edge cases |

Current status: **100 pairs delivered** (47 v1 + 20 production + 33 supplement).

## 7. Audit Logging

### 7.1 Field Spec (identity_match_audit table)

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| interaction_id | TEXT | Call/interaction being processed |
| candidate_a_id | UUID | First contact/record |
| candidate_b_id | UUID | Second contact/record |
| name_a | TEXT | Name of first candidate |
| name_b | TEXT | Name of second candidate |
| phonetic_code_a | TEXT | Double Metaphone of A |
| phonetic_code_b | TEXT | Double Metaphone of B |
| similarity_score | NUMERIC | JW or Levenshtein score |
| match_strength | TEXT | 'strong' or 'weak' |
| anchors_found | JSONB | Array of anchor evidence |
| decision | TEXT | AUTO_MERGE / SUGGEST / REJECT / BLOCK |
| decision_reason | TEXT | Human-readable explanation |
| created_at | TIMESTAMPTZ | When decision was made |
| pipeline_version | TEXT | Version that made the decision |

## 8. Integration Points

- `classifyMatchStrength()` in process-call/index.ts and context-assembly/index.ts
- `find_fuzzy_alias_matches()` SQL function
- `find_contact_by_name_or_alias()` SQL function
- `match_contacts_by_names_or_aliases()` RPC
- `normalizeAliasTerms()` utility (min length 4 chars = short-token gate)

## 9. Assumptions (Awaiting CHAD Decision)

1. **Phonetic thresholds**: JW >= 0.85 standard, >= 0.90 for 4-char codes accepted as defaults (STRAT-approved)
2. **English people-names only** for v1 (no internationalization)
3. **Zero false-merge tolerance** — prefer false negatives over false positives
4. **Integration point**: Final match gate + candidate-gen noise suppression
