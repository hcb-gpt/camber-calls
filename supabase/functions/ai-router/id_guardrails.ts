type IdField = "span_id" | "interaction_id";

export interface IdGuardrailWarning {
  field: IdField;
  code: string;
  message: string;
  raw: string;
  canonical: string;
}

export interface IdGuardrailResult {
  raw_span_id: string;
  raw_interaction_id: string;
  span_id: string;
  interaction_id: string;
  warnings: IdGuardrailWarning[];
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const INTERACTION_ID_RE = /^cll_[A-Za-z0-9]+$/;
const CONFUSABLE_INTERACTION_PREFIX_RE = /^c[1il|][1il|]_$/i;

// Keep this map intentionally narrow and explicit for OCR-confusable chars
// seen in interaction/span IDs. We do not mutate source evidence in place.
const CONFUSABLE_CHAR_MAP: Record<string, string> = {
  "\u0430": "a", // Cyrillic a
  "\u0431": "b", // Cyrillic be
  "\u0435": "e", // Cyrillic ie
  "\u043E": "o", // Cyrillic o
  "\u0440": "p", // Cyrillic er
  "\u0441": "c", // Cyrillic es
  "\u0445": "x", // Cyrillic ha
  "\u0443": "y", // Cyrillic u
  "\u0456": "i", // Cyrillic i
  "\u0458": "j", // Cyrillic je
  "\u0491": "r", // Cyrillic ghe with upturn
  "\u03B1": "a", // Greek alpha
  "\u03BF": "o", // Greek omicron
  "\u03C1": "p", // Greek rho
  "\u03C7": "x", // Greek chi
  "\u03B9": "i", // Greek iota
  "\u03BA": "k", // Greek kappa
  "\u0391": "A", // Greek Alpha
  "\u039F": "O", // Greek Omicron
  "\u03A1": "P", // Greek Rho
  "\u03A7": "X", // Greek Chi
  "\u0406": "I", // Cyrillic I
};

function toNfkc(input: string): string {
  try {
    return input.normalize("NFKC");
  } catch {
    return input;
  }
}

function mapConfusableChars(input: string): string {
  let out = "";
  for (const ch of input) out += CONFUSABLE_CHAR_MAP[ch] ?? ch;
  return out;
}

function containsNonAscii(input: string): boolean {
  return /[^\x20-\x7E]/.test(input);
}

function normalizeSpanId(
  raw: string,
  warnings: IdGuardrailWarning[],
): string {
  const trimmed = raw.trim();
  const nfkc = toNfkc(trimmed);
  const mapped = mapConfusableChars(nfkc);
  const candidate = mapped.toLowerCase();
  const rawValid = UUID_RE.test(trimmed);
  const candidateValid = UUID_RE.test(candidate);

  if (containsNonAscii(trimmed)) {
    warnings.push({
      field: "span_id",
      code: "span_id_non_ascii",
      message: "span_id contains non-ASCII characters; confusable normalization evaluated",
      raw: trimmed,
      canonical: candidate,
    });
  }
  if (nfkc !== trimmed) {
    warnings.push({
      field: "span_id",
      code: "span_id_nfkc_normalized",
      message: "span_id required Unicode normalization",
      raw: trimmed,
      canonical: candidate,
    });
  }
  if (mapped !== nfkc) {
    warnings.push({
      field: "span_id",
      code: "span_id_confusable_chars_mapped",
      message: "span_id included confusable characters that mapped to ASCII lookalikes",
      raw: trimmed,
      canonical: candidate,
    });
  }
  if (!rawValid && candidateValid) {
    warnings.push({
      field: "span_id",
      code: "span_id_canonicalized",
      message: "span_id canonicalized to valid UUID for safe DB key usage",
      raw: trimmed,
      canonical: candidate,
    });
    return candidate;
  }
  if (!rawValid && !candidateValid) {
    warnings.push({
      field: "span_id",
      code: "span_id_invalid_format",
      message: "span_id is not a valid UUID even after normalization",
      raw: trimmed,
      canonical: candidate,
    });
  }
  // Lowercase canonical form for stable UUID keying.
  return rawValid ? trimmed.toLowerCase() : trimmed;
}

function normalizeInteractionId(
  raw: string,
  warnings: IdGuardrailWarning[],
): string {
  const trimmed = raw.trim();
  const nfkc = toNfkc(trimmed);
  let mapped = mapConfusableChars(nfkc);

  if (containsNonAscii(trimmed)) {
    warnings.push({
      field: "interaction_id",
      code: "interaction_id_non_ascii",
      message: "interaction_id contains non-ASCII characters; confusable normalization evaluated",
      raw: trimmed,
      canonical: mapped,
    });
  }
  if (nfkc !== trimmed) {
    warnings.push({
      field: "interaction_id",
      code: "interaction_id_nfkc_normalized",
      message: "interaction_id required Unicode normalization",
      raw: trimmed,
      canonical: mapped,
    });
  }

  const prefix = mapped.slice(0, 4);
  if (CONFUSABLE_INTERACTION_PREFIX_RE.test(prefix) && prefix !== "cll_") {
    mapped = `cll_${mapped.slice(4)}`;
    warnings.push({
      field: "interaction_id",
      code: "interaction_id_confusable_prefix",
      message: "interaction_id prefix looked OCR-confusable (for example c11_); canonicalized to cll_",
      raw: trimmed,
      canonical: mapped,
    });
  }

  if (!INTERACTION_ID_RE.test(trimmed) && INTERACTION_ID_RE.test(mapped)) {
    warnings.push({
      field: "interaction_id",
      code: "interaction_id_canonicalized",
      message: "interaction_id canonicalized to expected cll_* format",
      raw: trimmed,
      canonical: mapped,
    });
    return mapped;
  }
  if (!INTERACTION_ID_RE.test(trimmed) && !INTERACTION_ID_RE.test(mapped)) {
    warnings.push({
      field: "interaction_id",
      code: "interaction_id_unexpected_format",
      message: "interaction_id did not match expected cll_* format after normalization",
      raw: trimmed,
      canonical: mapped,
    });
  }
  return INTERACTION_ID_RE.test(trimmed) ? trimmed : mapped;
}

export function normalizeIdsForAttribution(input: {
  span_id: string;
  interaction_id: string;
}): IdGuardrailResult {
  const warnings: IdGuardrailWarning[] = [];
  const raw_span_id = String(input.span_id ?? "");
  const raw_interaction_id = String(input.interaction_id ?? "");

  const span_id = normalizeSpanId(raw_span_id, warnings);
  const interaction_id = normalizeInteractionId(raw_interaction_id, warnings);

  return {
    raw_span_id,
    raw_interaction_id,
    span_id,
    interaction_id,
    warnings,
  };
}

