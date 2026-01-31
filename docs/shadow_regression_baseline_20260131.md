# Shadow Regression Baseline Report

**Date:** 2026-01-31T20:21:55Z  
**Sample Size:** 30 production calls  
**Pipeline Version:** v3.8.8 (admin-reseed v1.3.0, segment-llm v1.1.0)

## Summary

| Metric | Value |
|--------|-------|
| Total Interactions | 30 |
| Pass Rate | 100% |
| Zero Gap | 100% |
| Fallback Rate | 0% |

## Span Distribution

| Spans | Count | Percentage |
|-------|-------|------------|
| 1 span | 18 | 60.0% |
| 2 spans | 4 | 13.3% |
| 3 spans | 6 | 20.0% |
| 4 spans | 2 | 6.6% |

## Transcript Size Analysis

| Statistic | Value |
|-----------|-------|
| Min | 56 chars |
| Max | 23,808 chars |
| Median | 1,174 chars |
| Average | 3,757 chars |

## Long Transcript Quality (>2000 chars)

| Metric | Value |
|--------|-------|
| Long transcripts | 11 (36%) |
| Long with single span | 0 ✅ |
| Long with multiple spans | 11 |
| Multi-span rate | 100% |

## Multi-Span Calls Detail

| Interaction ID | Transcript Chars | Spans |
|----------------|------------------|-------|
| cll_06E11WMEX5VJB3KXEE1JRW04T8 | 23,808 | 4 |
| cll_06E11RXMFXVBK7Q9VWT9DPH0TC | 10,873 | 3 |
| cll_06E0P6KYB5V7S5VYQA8ZTRQM4W | 15,016 | 3 |
| cll_06E0YBM9MHYV50044CYDE65C94 | 12,471 | 3 |
| cll_06E0PACQH1ZCN3YNBTM8K9J54R | 9,164 | 4 |
| cll_06E118603XV5F7AXAJMQVR2C8R | 6,485 | 2 |
| cll_06E0QPHWXXTSH2AC66B2FGCDAM | 6,299 | 3 |
| cll_06E0QS9BV5SXK4YA55BH86M9BM | 4,170 | 3 |
| cll_06E0Q4VSPNZQDE4WSXMK3C4230 | 4,231 | 3 |
| cll_06E0QR4BQSTVB049CNS9V5JK60 | 4,150 | 2 |
| cll_06E10WNC21THSCKGD5D9PD6PAR | 3,149 | 2 |
| cll_06E11A4G1XTJS61HAMMAWDB19C | 1,184 | 2 |

## Proposed SLO Thresholds

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| `gap` | = 0 | **HARD** - CORI invariant |
| `uncovered_spans` | = 0 | **HARD** - Coverage invariant |
| `double_covered` | = 0 | **HARD** - No duplicate attributions |
| `fallback_rate` | < 10% | **SOFT** - Monitor LLM health |
| `pass_rate` | = 100% | **HARD** - Pipeline reliability |
| `multi_span_rate` (>2k chars) | > 80% | **SOFT** - Chunking quality |

## Key Findings

1. **Chunking quality is good**: 100% of long transcripts (>2000 chars) are properly segmented into multiple spans
2. **CORI invariant holds**: Zero gap across all 30 calls
3. **No fallback needed**: LLM segmentation succeeded for all calls without falling back to deterministic split
4. **Attribution coverage**: Every span has exactly one attribution (no uncovered, no double-covered)

## Raw Data

CSV file: `/tmp/shadow_regression_20260131_151009.csv`

```csv
interaction_id,status,generation,spans_total,spans_active,attributions,review_queue,gap,fallback,transcript_chars,error
cll_06E1AX8T2NZJQ560Q2FJ7BZAKM,pass,0,0,1,1,0,0,false,916,
cll_06E12ADVP5X353BX2WJWJHB7VR,pass,0,0,1,1,0,0,false,264,
...
```
