# Phone Capture Gap Fix v2.0

> Reconstructed by DEV-1 from TRAM receipts + live codebase.
> Original authored by DATA (receipt: `phone_capture_gap_fix_v2_retargeted_to_raw_snapshot`).
> Supersedes v1 (which targeted transcript-only extraction).

## 1. Problem Statement

~33% of calls in `interactions` lack `contact_phone` data. Without phone data,
identity matching falls back to name-only, which produces false positives
(e.g., Brian Dove matched to Brian Young's project).

STRAT analysis found **62 of 72 phoneless rows** have a US 10-digit number
buried in `calls_raw.raw_snapshot_json` — the structured payload from Zapier/webhook
ingestion.

## 2. Approach: Layered Extraction

Three extraction layers, tried in order of confidence:

### Layer 1: Structured JSON Fields (High Confidence)

Extract from well-known keys in `raw_snapshot_json`:

```sql
COALESCE(
  raw_json->>'from_phone',
  raw_json->>'to_phone',
  raw_json->>'caller_phone',
  raw_json->'contact'->>'phone',
  raw_json->>'customer_phone',
  raw_json->>'phone_number'
)
```

### Layer 2: Regex Scan of JSON Text (Medium Confidence)

Scan the full JSON text for US 10-digit phone patterns:

```
Pattern: \+?1?[\s.-]?\(?[2-9]\d{2}\)?[\s.-]?\d{3}[\s.-]?\d{4}
```

**Safety Filters:**
- Invalid area codes (0XX, 1XX) → rejected
- All-same-digit patterns (e.g., 555-555-5555) → rejected
- Date-like patterns (MMDDYYYY, YYYYMMDD) → rejected
- Owner phone match → excluded (we want OTHER party)
- Repeated digits (e.g., 000, 111) → rejected

### Layer 3: Transcript Speaker Labels (Fallback)

Original v1 approach — extract E.164-formatted numbers from speaker labels:

```
Pattern: /^(\+[1-9]\d{6,14})\s*:/m
```

## 3. SQL Functions

### 3.1 util.normalize_us_phone(raw TEXT) → TEXT

Strips formatting, validates 10-digit US number, returns E.164 format (+1XXXXXXXXXX).

### 3.2 util.extract_us_phone_from_text(text_body TEXT) → TABLE

Scans text for US phone patterns with safety filters. Returns (phone, source, confidence).

### 3.3 util.extract_phone_from_raw_snapshot(raw_json JSONB, owner_phone TEXT) → TABLE

Layered extraction from JSON payload:
1. Check structured fields
2. Regex scan JSON text
3. Exclude owner phone
4. Return (phone, source, confidence)

### 3.4 util.extract_other_party_phone(raw_json JSONB, transcript TEXT, owner_phone TEXT) → TABLE

Combined function — all three layers:
1. `extract_phone_from_raw_snapshot` (layers 1+2)
2. Transcript speaker label extraction (layer 3)
3. Returns best match with source and confidence

## 4. TypeScript Integration (persist_call_event)

For the `process-call` edge function, add extraction in the normalization step:

```typescript
function extractPhoneFromRawSnapshot(
  rawJson: Record<string, any>,
  ownerPhone?: string
): { phone: string; source: string; confidence: number } | null {
  // Layer 1: Structured fields
  const structuredKeys = [
    'from_phone', 'to_phone', 'caller_phone',
    'customer_phone', 'phone_number'
  ];
  for (const key of structuredKeys) {
    const val = rawJson[key];
    if (val && typeof val === 'string') {
      const normalized = normalizeUSPhone(val);
      if (normalized && normalized !== ownerPhone) {
        return { phone: normalized, source: `json.${key}`, confidence: 0.95 };
      }
    }
  }
  // Check nested contact.phone
  if (rawJson.contact?.phone) {
    const normalized = normalizeUSPhone(rawJson.contact.phone);
    if (normalized && normalized !== ownerPhone) {
      return { phone: normalized, source: 'json.contact.phone', confidence: 0.95 };
    }
  }

  // Layer 2: Regex scan of JSON text
  const jsonText = JSON.stringify(rawJson);
  const phonePattern = /\+?1?[\s.-]?\(?([2-9]\d{2})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})/g;
  let match;
  while ((match = phonePattern.exec(jsonText)) !== null) {
    const digits = match[1] + match[2] + match[3];
    const normalized = `+1${digits}`;
    if (normalized !== ownerPhone && isValidUSPhone(digits)) {
      return { phone: normalized, source: 'json_regex', confidence: 0.75 };
    }
  }

  return null;
}

function normalizeUSPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits[0] === '1') return `+${digits}`;
  return null;
}

function isValidUSPhone(digits: string): boolean {
  if (digits.length !== 10) return false;
  const areaCode = digits.slice(0, 3);
  if (areaCode[0] === '0' || areaCode[0] === '1') return false;
  if (/^(.)\1{9}$/.test(digits)) return false; // all same digit
  if (/^(.)\1{2}/.test(areaCode)) return false; // repeated area code digits
  return true;
}
```

## 5. Dry-Run Measurement Query

```sql
SELECT
  COUNT(*) AS total_phoneless,
  COUNT(*) FILTER (WHERE util.extract_other_party_phone(
    cr.raw_snapshot_json, i.contact_phone, cr.owner_phone
  ) IS NOT NULL) AS would_capture,
  ROUND(100.0 * COUNT(*) FILTER (WHERE util.extract_other_party_phone(
    cr.raw_snapshot_json, i.contact_phone, cr.owner_phone
  ) IS NOT NULL) / NULLIF(COUNT(*), 0), 1) AS capture_pct
FROM interactions i
JOIN calls_raw cr ON cr.interaction_id = i.interaction_id
WHERE i.contact_phone IS NULL;
```

## 6. Backfill (with Audit)

```sql
-- Backfill: only high + medium confidence, with audit trail
WITH candidates AS (
  SELECT
    i.interaction_id,
    i.contact_phone AS old_phone,
    (util.extract_other_party_phone(
      cr.raw_snapshot_json, i.contact_phone, cr.owner_phone
    )).*
  FROM interactions i
  JOIN calls_raw cr ON cr.interaction_id = i.interaction_id
  WHERE i.contact_phone IS NULL
)
INSERT INTO phone_capture_audit (interaction_id, old_phone, new_phone, source, confidence, applied_at)
SELECT interaction_id, old_phone, phone, source, confidence, NOW()
FROM candidates
WHERE confidence >= 0.75;

-- Then update interactions (separate step, after audit review):
-- UPDATE interactions SET contact_phone = audit.new_phone
-- FROM phone_capture_audit audit
-- WHERE interactions.interaction_id = audit.interaction_id
--   AND audit.confidence >= 0.75;
```

## 7. Execution Sequence

| Step | Owner | Action | Gate |
|------|-------|--------|------|
| 1 | DATA | Create util schema + functions | None |
| 2 | DATA | Create audit table | None |
| 3 | CHAD | Approve dry-run | **CHAD GATE** |
| 4 | DATA | Run dry-run measurement | None |
| 5 | DATA | Review results, report to CHAD | None |
| 6 | DEV | Patch persist_call_event with TS extraction | After CHAD approves |
| 7 | DATA | Run backfill with audit trail | After Step 6 |
| 8 | DEV | Replay affected calls | After Step 7 |

**Current status:** Steps 1-2 ready (migrations delivered). Waiting on Step 3 (CHAD gate).
