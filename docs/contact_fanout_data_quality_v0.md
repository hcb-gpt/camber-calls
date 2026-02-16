# Contact Fanout Data Quality Report v0

**Date:** 2026-02-15
**Author:** DATA-1
**Status:** Baseline (pre-WP-4 GT evaluation)
**Scope:** Phone-to-project association quality in production DB (gandalf)

---

## 1. Existing Infrastructure

| Table/View | Rows | Purpose |
|---|---|---|
| `contact_fanout` | 392 | Materialized fanout metrics per contact |
| `project_contacts` | 262 | Contact-to-project mapping (role, trade, is_active, source) |
| `v_contact_project_affinity` | (view) | Affinity derived from interactions call history |
| `v_contact_fanout` | (view) | Computes fanout from project_contacts + correspondent_project_affinity |
| `correspondent_project_affinity` | -- | Weight-based affinity table |

## 2. Interaction Volume

| Metric | Value |
|---|---|
| Total interactions (non-shadow) | 629 |
| Distinct phones | 112 |
| Distinct contacts | 70 |
| With project_id | 365 (58%) |
| With contact_id | 482 (77%) |
| With both project + contact | 357 (57%) |

`calls_raw` has 705 rows / 129 phones but no `project_id` or `contact_id`.
**`interactions` is the authoritative source** for phone-to-project mapping.

## 3. Phone-to-Project Distribution (External Contacts Only)

| Projects per phone | Phone count | Interactions | % of phones |
|---|---|---|---|
| 1 (anchored) | 29 | 74 | 74.4% |
| 2 (semi-anchored) | 6 | 32 | 15.4% |
| 3 | 2 | 36 | 5.1% |
| 4 | 1 | 15 | 2.6% |
| 5 | 1 | 18 | 2.6% |

**74% of external phones map to exactly 1 project.** This is high-signal for attribution fallback.

## 4. Anchoring by Contact Type

| Type | 1:1 anchored | Semi (2) | Multi (3+) | Total |
|---|---|---|---|---|
| subcontractor | 12 | 2 | 3 | 17 |
| supplier | 7 | 1 | 1 | 9 |
| client | 6 | 2 | 0 | 8 |
| professional | 4 | 1 | 0 | 5 |

**Clients are 100% anchored or semi-anchored.** The 2-project clients (Shayelyn Woodbery, David Woodbery) are correct: both map to Woodbery Residence + Woodbery Barns.

## 5. Multi-Project Contacts (Top 10)

| Contact | Type | Projects | Calls | Project Names |
|---|---|---|---|---|
| Brian Dove | sub | 5 | 18 | Hurley, Sittler(M), Skelton, White, Young |
| Malcolm Hetzer | sub | 4 | 15 | Hurley, Permar, Sittler(M), Winship |
| Flynt Treadaway | supplier | 3 | 24 | Permar, Sittler(M), Winship |
| Zach Givens | sub | 3 | 12 | Sittler(A), White, Winship |
| Shayelyn Woodbery | client | 2 | 10 | Woodbery Barns, Woodbery Residence |
| Amy Champion | supplier | 2 | 5 | Hurley, Winship |
| David Woodbery | client | 2 | 5 | Woodbery Barns, Woodbery Residence |
| Gatlin Hawkins | sub | 2 | 4 | Hurley, Winship |
| Brandon Hightower | professional | 2 | 4 | Hurley, Permar |
| Randy Bryan | sub | 2 | 4 | Moss, Sittler(M) |

## 6. Sittler Contamination

Three Sittler projects account for **62 phantom attributions** in interactions:

| Project | Attributed interactions |
|---|---|
| Sittler Residence (Madison) | 27 |
| Sittler Residence (Bishop) | 19 |
| Sittler Residence (Athens) | 16 |

"Sittler" is Zack Sittler, HCB staff (the builder answering calls). These are not client projects. Every Sittler attribution is a staff-name leak.

### Impact on fanout

Excluding Sittler from the distribution:

| Projects per phone | Phone count | Interactions | % of phones |
|---|---|---|---|
| 1 (anchored) | 30 (+1) | 75 | 76.9% |
| 2 (semi-anchored) | 7 (+1) | 53 | 17.9% |
| 3 | 1 (-1) | 14 | 2.6% |
| 4 | 1 | 17 | 2.6% |

Sittler exclusion bumps anchoring from 74% to **77%** and reduces the maximum multi-project count from 5 to 4.

### Sittler contamination in project_contacts

Most `project_contacts` rows for subcontractors have `source='data_inferred'` and link each sub to ALL projects (including Sittler variants). Examples:

- Brian Dove: 12 project_contacts rows (GT: Woodbery framing)
- Malcolm Hetzer: 12 project_contacts rows (GT: Winship electrical)
- Flynt Treadaway: 12 project_contacts rows (GT: Winship+Woodbery)

This over-broad mapping defeats contact-based attribution narrowing.

## 7. What Works

- **Client contacts are correctly anchored:** Lou Winship -> Winship (1:1), Shayelyn Woodbery -> Woodbery (1:1, anchored)
- **Ron C Persall** -> Winship only (anchored, source=chad_directive). Correct per GT.
- **Affinity view** (`v_contact_project_affinity`) has useful signal: Malcolm Hetzer 57% Winship (correct), Flynt Treadaway 76% Permar
- **Fanout classes** in `contact_fanout`: anchored=47, semi_anchored=10, drifter=4, floater=20, unknown=311

## 8. Recommendations

1. **Source table:** Use `interactions` for deriving phone-to-project associations. It has both `contact_id` and `project_id` (calls_raw has neither).

2. **Sittler exclusion:** Exclude all Sittler Residence variants from fanout computation and attribution candidacy. These are staff-name leaks, not real projects.

3. **Data quality fix for project_contacts:** The `data_inferred` source rows are over-broad. Either prune them to match actual affinity data, or add a `signal_strength`/`weight` column so context-assembly can filter on high-confidence associations.

4. **Leverage affinity view:** `v_contact_project_affinity` already computes call-based affinity with `affinity_pct` and `affinity_rank`. For attribution fallback, reading `affinity_rank=1` for a contact is the highest-signal approach.

5. **Case normalization:** GT registry has "Winship" vs "winship" inconsistency. Normalize to lowercase for matching.

---

*This report establishes the baseline for comparing attribution accuracy before and after the world model sprint (WP-1 through WP-4).*
