export type IdField = "interaction_id" | "span_id";
export type IdIssueSeverity = "warning" | "error";

export interface IdGuardIssue {
  field: IdField;
  severity: IdIssueSeverity;
  code: string;
  message: string;
  as_received: string;
  suggested_canonical?: string;
}

const INTERACTION_ID_RE = /^cll_[A-Za-z0-9_]+$/;
const SPAN_ID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function isAsciiPrintable(value: string): boolean {
  return !/[^\x20-\x7E]/.test(value);
}

function addIssue(
  issues: IdGuardIssue[],
  field: IdField,
  severity: IdIssueSeverity,
  code: string,
  message: string,
  as_received: string,
  suggested_canonical?: string,
) {
  issues.push({
    field,
    severity,
    code,
    message,
    as_received,
    suggested_canonical,
  });
}

function suggestInteractionCanonical(raw: string): string | undefined {
  const idx = raw.indexOf("_");
  if (idx < 0) return undefined;
  const suffix = raw.slice(idx + 1);
  if (!suffix) return undefined;
  return `cll_${suffix}`;
}

function validateInteractionId(raw: unknown, issues: IdGuardIssue[]) {
  if (raw == null) return;
  if (typeof raw !== "string") {
    addIssue(
      issues,
      "interaction_id",
      "error",
      "interaction_id_not_string",
      "interaction_id must be a string.",
      String(raw),
    );
    return;
  }
  const value = raw.trim();
  if (!value) {
    addIssue(
      issues,
      "interaction_id",
      "error",
      "interaction_id_empty",
      "interaction_id must not be empty.",
      value,
    );
    return;
  }

  if (!isAsciiPrintable(value)) {
    addIssue(
      issues,
      "interaction_id",
      "error",
      "interaction_id_non_ascii",
      "interaction_id contains non-ASCII characters (possible OCR confusable input).",
      value,
      suggestInteractionCanonical(value),
    );
  }

  if (!value.startsWith("cll_") && /^c[1lI][1lI]_/.test(value)) {
    addIssue(
      issues,
      "interaction_id",
      "warning",
      "interaction_id_confusable_prefix",
      "interaction_id prefix looks OCR-confusable (c11_/cl1_/c1l_).",
      value,
      suggestInteractionCanonical(value),
    );
  } else if (value.startsWith("CLL_")) {
    addIssue(
      issues,
      "interaction_id",
      "warning",
      "interaction_id_uppercase_prefix",
      "interaction_id prefix uses uppercase; canonical prefix is cll_.",
      value,
      `cll_${value.slice(4)}`,
    );
  }

  if (!INTERACTION_ID_RE.test(value)) {
    addIssue(
      issues,
      "interaction_id",
      "error",
      "interaction_id_invalid_format",
      "interaction_id must match ^cll_[A-Za-z0-9_]+$.",
      value,
      suggestInteractionCanonical(value),
    );
  }
}

function validateSpanId(raw: unknown, issues: IdGuardIssue[]) {
  if (raw == null) return;
  if (typeof raw !== "string") {
    addIssue(
      issues,
      "span_id",
      "error",
      "span_id_not_string",
      "span_id must be a string.",
      String(raw),
    );
    return;
  }
  const value = raw.trim();
  if (!value) {
    addIssue(
      issues,
      "span_id",
      "error",
      "span_id_empty",
      "span_id must not be empty.",
      value,
    );
    return;
  }

  if (!isAsciiPrintable(value)) {
    addIssue(
      issues,
      "span_id",
      "error",
      "span_id_non_ascii",
      "span_id contains non-ASCII characters (possible OCR confusable input).",
      value,
    );
  }

  if (!/^[0-9a-fA-F-]+$/.test(value)) {
    addIssue(
      issues,
      "span_id",
      "error",
      "span_id_invalid_charset",
      "span_id includes characters outside UUID charset [0-9a-fA-F-].",
      value,
    );
  }

  if (!SPAN_ID_RE.test(value)) {
    addIssue(
      issues,
      "span_id",
      "error",
      "span_id_invalid_format",
      "span_id must match canonical UUID format xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.",
      value,
    );
  }
}

export function validateAttributionIds(input: {
  interaction_id?: unknown;
  span_id?: unknown;
}): IdGuardIssue[] {
  const issues: IdGuardIssue[] = [];
  validateInteractionId(input.interaction_id, issues);
  validateSpanId(input.span_id, issues);
  return issues;
}

export function hasIdGuardErrors(issues: IdGuardIssue[]): boolean {
  return issues.some((issue) => issue.severity === "error");
}

export function summarizeIdGuardWarnings(issues: IdGuardIssue[]): string[] {
  return issues.map((issue) => `id_guard:${issue.field}:${issue.code}`);
}
