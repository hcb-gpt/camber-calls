#!/usr/bin/env -S deno run --allow-read --allow-write

/**
 * Convert world-model fact JSONL into a seed SQL file for:
 * - public.evidence_events (manual rows, grouped by project_id + source_batch_id)
 * - public.project_facts (one row per input fact)
 *
 * The generated SQL performs an idempotent-ish insert pattern:
 * - evidence_events uses deterministic source_id + ON CONFLICT DO NOTHING
 * - project_facts uses WHERE NOT EXISTS on a natural-key comparison
 */

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

type JsonObject = { [key: string]: JsonValue };

interface CliOptions {
  inputPath: string;
  outputPath: string;
  summaryOutPath: string | null;
  defaultSourceBatchId: string | null;
  defaultSourceRunId: string;
  generatedAtIso: string;
}

interface InputFactRow {
  lineNo: number;
  projectId: string;
  asOfAtIso: string;
  observedAtIso: string;
  factKind: string;
  factPayload: JsonValue;
  evidenceEventId: string | null;
  interactionId: string | null;
  sourceSpanId: string | null;
  sourceCharStart: number | null;
  sourceCharEnd: number | null;
  sourceBatchId: string | null;
  sourceRunId: string | null;
  sourceMetadata: JsonObject | null;
}

interface SummaryData {
  totalRows: number;
  rowsWithProvidedEvidenceEventId: number;
  rowsNeedingManualEvidence: number;
  manualEvidenceGroups: number;
  rowsByProject: Map<string, number>;
  rowsByFactKind: Map<string, number>;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ALLOWED_KEYS = new Set([
  "project_id",
  "as_of_at",
  "observed_at",
  "fact_kind",
  "fact_payload",
  "evidence_event_id",
  "interaction_id",
  "source_span_id",
  "source_char_start",
  "source_char_end",
  "source_batch_id",
  "source_run_id",
  "source_metadata",
]);

function usage(): string {
  return [
    "Usage:",
    "  deno run --allow-read --allow-write scripts/world_model/seed_jsonl_to_sql.ts \\",
    "    --input <facts.jsonl> --output <seed.sql> [--summary-out <summary.txt>] \\",
    "    [--default-source-batch-id <batch_id>] [--default-source-run-id <run_id>] \\",
    "    [--generated-at <ISO8601>]",
    "",
    "Input JSONL row schema (strict):",
    "  Required: project_id, as_of_at, observed_at, fact_kind, fact_payload",
    "  Optional: evidence_event_id, interaction_id, source_span_id, source_char_start,",
    "            source_char_end, source_batch_id, source_run_id, source_metadata",
    "",
    "Rule:",
    "  Each row must provide either evidence_event_id, or source_batch_id",
    "  (or a --default-source-batch-id fallback).",
  ].join("\n");
}

function fail(message: string): never {
  console.error(`ERROR: ${message}`);
  Deno.exit(1);
}

function parseArgs(argv: string[]): CliOptions {
  let inputPath: string | null = null;
  let outputPath: string | null = null;
  let summaryOutPath: string | null = null;
  let defaultSourceBatchId: string | null = null;
  let defaultSourceRunId = "world_model_seed_tool_v0";
  let generatedAtIso: string | null = null;

  const nextValue = (i: number, arg: string): string => {
    if (i + 1 >= argv.length) fail(`Missing value after ${arg}`);
    return argv[i + 1];
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    if (arg === "--help" || arg === "-h") {
      console.log(usage());
      Deno.exit(0);
    }

    if (arg === "--input") {
      inputPath = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--input=")) {
      inputPath = arg.slice("--input=".length);
      continue;
    }

    if (arg === "--output") {
      outputPath = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--output=")) {
      outputPath = arg.slice("--output=".length);
      continue;
    }

    if (arg === "--summary-out") {
      summaryOutPath = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--summary-out=")) {
      summaryOutPath = arg.slice("--summary-out=".length);
      continue;
    }

    if (arg === "--default-source-batch-id") {
      defaultSourceBatchId = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--default-source-batch-id=")) {
      defaultSourceBatchId = arg.slice("--default-source-batch-id=".length);
      continue;
    }

    if (arg === "--default-source-run-id") {
      defaultSourceRunId = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--default-source-run-id=")) {
      defaultSourceRunId = arg.slice("--default-source-run-id=".length);
      continue;
    }

    if (arg === "--generated-at") {
      generatedAtIso = nextValue(i, arg);
      i++;
      continue;
    }
    if (arg.startsWith("--generated-at=")) {
      generatedAtIso = arg.slice("--generated-at=".length);
      continue;
    }

    fail(`Unknown argument: ${arg}`);
  }

  if (!inputPath) fail("--input is required");
  if (!outputPath) fail("--output is required");

  const normalizedDefaultBatch = normalizeOptionalString(defaultSourceBatchId);
  const normalizedRunId = normalizeOptionalString(defaultSourceRunId);
  if (!normalizedRunId) fail("--default-source-run-id must be non-empty");

  const generatedAt = normalizeOptionalString(generatedAtIso) ??
    new Date().toISOString();

  return {
    inputPath,
    outputPath,
    summaryOutPath: normalizeOptionalString(summaryOutPath),
    defaultSourceBatchId: normalizedDefaultBatch,
    defaultSourceRunId: normalizedRunId,
    generatedAtIso: parseIsoOrFail(generatedAt, "--generated-at"),
  };
}

function normalizeOptionalString(value: unknown): string | null {
  if (value == null) return null;
  const str = String(value).trim();
  return str.length > 0 ? str : null;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isJsonValue(value: unknown): value is JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return true;
  }
  if (Array.isArray(value)) {
    return value.every((item) => isJsonValue(item));
  }
  if (isPlainObject(value)) {
    return Object.values(value).every((item) => isJsonValue(item));
  }
  return false;
}

function parseIsoOrFail(raw: string, fieldName: string): string {
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) {
    fail(`${fieldName} must be ISO8601; received: ${raw}`);
  }
  return d.toISOString();
}

function assertUuid(raw: string, fieldName: string): string {
  if (!UUID_RE.test(raw)) {
    fail(`${fieldName} must be UUID; received: ${raw}`);
  }
  return raw.toLowerCase();
}

function assertInteger(raw: unknown, fieldName: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw)) {
    fail(`${fieldName} must be integer; received: ${JSON.stringify(raw)}`);
  }
  return raw;
}

function stableStringify(value: JsonValue): string {
  if (value === null) return "null";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return "null";
    return String(value);
  }
  if (typeof value === "boolean") return value ? "true" : "false";
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }
  const entries = Object.entries(value).sort(([a], [b]) => a.localeCompare(b));
  return `{${
    entries
      .map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`)
      .join(",")
  }}`;
}

function sqlQuote(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

function sqlText(value: string | null): string {
  return value === null ? "null::text" : `${sqlQuote(value)}::text`;
}

function sqlUuid(value: string | null): string {
  return value === null ? "null::uuid" : `${sqlQuote(value)}::uuid`;
}

function sqlInteger(value: number | null): string {
  return value === null ? "null::integer" : String(value);
}

function sqlTimestamptz(value: string): string {
  return `${sqlQuote(value)}::timestamptz`;
}

function sqlJsonb(value: JsonValue): string {
  return `${sqlQuote(stableStringify(value))}::jsonb`;
}

function sqlNullableJsonb(value: JsonValue | null): string {
  return value === null ? "null::jsonb" : sqlJsonb(value);
}

function parseInputRows(options: CliOptions, rawText: string): InputFactRow[] {
  const rows: InputFactRow[] = [];
  const lines = rawText.split(/\r?\n/);

  for (let i = 0; i < lines.length; i++) {
    const lineNo = i + 1;
    const line = lines[i].trim();
    if (!line) continue;

    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch (err) {
      fail(`Line ${lineNo}: invalid JSON (${(err as Error).message})`);
    }

    if (!isPlainObject(parsed)) {
      fail(`Line ${lineNo}: row must be a JSON object`);
    }

    for (const key of Object.keys(parsed)) {
      if (!ALLOWED_KEYS.has(key)) {
        fail(`Line ${lineNo}: unsupported key '${key}'`);
      }
    }

    const projectIdRaw = normalizeOptionalString(parsed.project_id);
    const asOfRaw = normalizeOptionalString(parsed.as_of_at);
    const observedRaw = normalizeOptionalString(parsed.observed_at);
    const factKindRaw = normalizeOptionalString(parsed.fact_kind);

    if (!projectIdRaw) fail(`Line ${lineNo}: project_id is required`);
    if (!asOfRaw) fail(`Line ${lineNo}: as_of_at is required`);
    if (!observedRaw) fail(`Line ${lineNo}: observed_at is required`);
    if (!factKindRaw) fail(`Line ${lineNo}: fact_kind is required`);
    if (!("fact_payload" in parsed)) {
      fail(`Line ${lineNo}: fact_payload is required`);
    }

    const factPayloadRaw = parsed.fact_payload;
    if (!isJsonValue(factPayloadRaw) || factPayloadRaw === null) {
      fail(`Line ${lineNo}: fact_payload must be non-null valid JSON`);
    }

    const evidenceEventIdRaw = normalizeOptionalString(
      parsed.evidence_event_id,
    );
    const interactionId = normalizeOptionalString(parsed.interaction_id);
    const sourceSpanIdRaw = normalizeOptionalString(parsed.source_span_id);
    const sourceBatchRowRaw = normalizeOptionalString(parsed.source_batch_id);
    const sourceRunId = normalizeOptionalString(parsed.source_run_id);

    let sourceMetadata: JsonObject | null = null;
    if (
      parsed.source_metadata !== undefined && parsed.source_metadata !== null
    ) {
      if (!isPlainObject(parsed.source_metadata)) {
        fail(`Line ${lineNo}: source_metadata must be an object when provided`);
      }
      if (!isJsonValue(parsed.source_metadata)) {
        fail(`Line ${lineNo}: source_metadata must be valid JSON object`);
      }
      sourceMetadata = parsed.source_metadata as JsonObject;
    }

    let sourceCharStart: number | null = null;
    let sourceCharEnd: number | null = null;
    if (
      parsed.source_char_start !== undefined ||
      parsed.source_char_end !== undefined
    ) {
      if (
        parsed.source_char_start === undefined ||
        parsed.source_char_end === undefined
      ) {
        fail(
          `Line ${lineNo}: source_char_start and source_char_end must be provided together`,
        );
      }
      sourceCharStart = assertInteger(
        parsed.source_char_start,
        `Line ${lineNo}: source_char_start`,
      );
      sourceCharEnd = assertInteger(
        parsed.source_char_end,
        `Line ${lineNo}: source_char_end`,
      );
      if (sourceCharStart < 0) {
        fail(`Line ${lineNo}: source_char_start must be >= 0`);
      }
      if (sourceCharEnd <= sourceCharStart) {
        fail(`Line ${lineNo}: source_char_end must be > source_char_start`);
      }
    }

    const projectId = assertUuid(projectIdRaw, `Line ${lineNo}: project_id`);
    const asOfAtIso = parseIsoOrFail(asOfRaw, `Line ${lineNo}: as_of_at`);
    const observedAtIso = parseIsoOrFail(
      observedRaw,
      `Line ${lineNo}: observed_at`,
    );

    const evidenceEventId = evidenceEventIdRaw
      ? assertUuid(evidenceEventIdRaw, `Line ${lineNo}: evidence_event_id`)
      : null;

    const sourceSpanId = sourceSpanIdRaw
      ? assertUuid(sourceSpanIdRaw, `Line ${lineNo}: source_span_id`)
      : null;

    const sourceBatchId = sourceBatchRowRaw ?? options.defaultSourceBatchId;

    if (!evidenceEventId && !sourceBatchId) {
      fail(
        `Line ${lineNo}: row needs evidence_event_id or source_batch_id (or --default-source-batch-id)`,
      );
    }

    rows.push({
      lineNo,
      projectId,
      asOfAtIso,
      observedAtIso,
      factKind: factKindRaw,
      factPayload: factPayloadRaw,
      evidenceEventId,
      interactionId,
      sourceSpanId,
      sourceCharStart,
      sourceCharEnd,
      sourceBatchId: evidenceEventId ? null : sourceBatchId,
      sourceRunId: evidenceEventId
        ? null
        : (sourceRunId ?? options.defaultSourceRunId),
      sourceMetadata,
    });
  }

  if (rows.length === 0) {
    fail("Input file has no JSONL rows");
  }

  return rows;
}

function buildSummary(rows: InputFactRow[]): SummaryData {
  const rowsByProject = new Map<string, number>();
  const rowsByFactKind = new Map<string, number>();
  const manualGroupKeys = new Set<string>();

  let rowsWithProvidedEvidenceEventId = 0;
  let rowsNeedingManualEvidence = 0;

  for (const row of rows) {
    rowsByProject.set(
      row.projectId,
      (rowsByProject.get(row.projectId) ?? 0) + 1,
    );
    rowsByFactKind.set(
      row.factKind,
      (rowsByFactKind.get(row.factKind) ?? 0) + 1,
    );

    if (row.evidenceEventId) {
      rowsWithProvidedEvidenceEventId += 1;
    } else {
      rowsNeedingManualEvidence += 1;
      manualGroupKeys.add(`${row.projectId}|${row.sourceBatchId}`);
    }
  }

  return {
    totalRows: rows.length,
    rowsWithProvidedEvidenceEventId,
    rowsNeedingManualEvidence,
    manualEvidenceGroups: manualGroupKeys.size,
    rowsByProject,
    rowsByFactKind,
  };
}

function validateManualGroupConsistency(rows: InputFactRow[]): void {
  const runIdByGroup = new Map<string, string>();
  for (const row of rows) {
    if (row.evidenceEventId) continue;
    const key = `${row.projectId}|${row.sourceBatchId}`;
    const runId = row.sourceRunId ?? "";
    const existing = runIdByGroup.get(key);
    if (existing && existing !== runId) {
      fail(
        `Inconsistent source_run_id for manual group ${key}: '${existing}' vs '${runId}'`,
      );
    }
    runIdByGroup.set(key, runId);
  }
}

function formatSummary(summary: SummaryData): string {
  const projectLines = Array.from(summary.rowsByProject.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([projectId, count]) => `  - ${projectId}: ${count}`);

  const kindLines = Array.from(summary.rowsByFactKind.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([factKind, count]) => `  - ${factKind}: ${count}`);

  return [
    "World Model Seed Summary",
    `rows_total: ${summary.totalRows}`,
    `rows_with_provided_evidence_event_id: ${summary.rowsWithProvidedEvidenceEventId}`,
    `rows_needing_manual_evidence_event: ${summary.rowsNeedingManualEvidence}`,
    `manual_evidence_groups: ${summary.manualEvidenceGroups}`,
    "counts_by_project_id:",
    ...(projectLines.length > 0 ? projectLines : ["  - none"]),
    "counts_by_fact_kind:",
    ...(kindLines.length > 0 ? kindLines : ["  - none"]),
  ].join("\n");
}

function buildSql(options: CliOptions, rows: InputFactRow[]): string {
  const valuesSql = rows
    .map((row) => {
      const metadataJson: JsonValue | null = row.sourceMetadata;
      return [
        "(",
        String(row.lineNo),
        ", ",
        sqlUuid(row.projectId),
        ", ",
        sqlTimestamptz(row.asOfAtIso),
        ", ",
        sqlTimestamptz(row.observedAtIso),
        ", ",
        sqlText(row.factKind),
        ", ",
        sqlJsonb(row.factPayload),
        ", ",
        sqlUuid(row.evidenceEventId),
        ", ",
        sqlText(row.interactionId),
        ", ",
        sqlUuid(row.sourceSpanId),
        ", ",
        sqlInteger(row.sourceCharStart),
        ", ",
        sqlInteger(row.sourceCharEnd),
        ", ",
        sqlText(row.sourceBatchId),
        ", ",
        sqlText(row.sourceRunId),
        ", ",
        sqlNullableJsonb(metadataJson),
        ")",
      ].join("");
    })
    .join(",\n      ");

  const generatedAtSql = sqlText(options.generatedAtIso);
  const inputFileSql = sqlText(options.inputPath);

  return `-- Generated by scripts/world_model/seed_jsonl_to_sql.ts
-- generated_at_utc: ${options.generatedAtIso}
-- input_file: ${options.inputPath}
-- rows: ${rows.length}
--
-- NOTE: This SQL mutates data when executed. Run intentionally via psql.

begin;

with input_rows as (
  select *
  from (
    values
      ${valuesSql}
  ) as v(
    line_no,
    project_id,
    as_of_at,
    observed_at,
    fact_kind,
    fact_payload,
    provided_evidence_event_id,
    interaction_id,
    source_span_id,
    source_char_start,
    source_char_end,
    source_batch_id,
    source_run_id,
    source_metadata
  )
),
manual_groups as (
  select
    ir.project_id,
    ir.source_batch_id,
    min(ir.as_of_at) as occurred_at_utc,
    max(ir.source_run_id) as source_run_id,
    count(*)::integer as row_count,
    jsonb_agg(ir.source_metadata) filter (where ir.source_metadata is not null) as source_metadata_rollup
  from input_rows ir
  where ir.provided_evidence_event_id is null
  group by ir.project_id, ir.source_batch_id
),
insert_manual_evidence as (
  insert into public.evidence_events (
    source_type,
    source_id,
    transcript_variant,
    occurred_at_utc,
    source_run_id,
    metadata
  )
  select
    'manual',
    concat('manual_seed:world_model_jsonl:', mg.project_id::text, ':', md5(mg.source_batch_id)),
    'baseline',
    mg.occurred_at_utc,
    mg.source_run_id,
    jsonb_build_object(
      'seed_tool', 'scripts/world_model/seed_jsonl_to_sql.ts',
      'seed_kind', 'world_model_seed_jsonl_v0',
      'generated_at_utc', ${generatedAtSql},
      'input_file', ${inputFileSql},
      'project_id', mg.project_id::text,
      'source_batch_id', mg.source_batch_id,
      'row_count', mg.row_count,
      'source_metadata_rollup', coalesce(mg.source_metadata_rollup, '[]'::jsonb)
    )
  from manual_groups mg
  on conflict (source_type, source_id, transcript_variant) do nothing
  returning evidence_event_id, source_id
),
resolved_manual as (
  select
    mg.project_id,
    mg.source_batch_id,
    ee.evidence_event_id
  from manual_groups mg
  join public.evidence_events ee
    on ee.source_type = 'manual'
   and ee.source_id = concat('manual_seed:world_model_jsonl:', mg.project_id::text, ':', md5(mg.source_batch_id))
   and ee.transcript_variant = 'baseline'
),
resolved_rows as (
  select
    ir.line_no,
    ir.project_id,
    ir.as_of_at,
    ir.observed_at,
    ir.fact_kind,
    ir.fact_payload,
    coalesce(ir.provided_evidence_event_id, rm.evidence_event_id) as evidence_event_id,
    ir.interaction_id,
    ir.source_span_id,
    ir.source_char_start,
    ir.source_char_end
  from input_rows ir
  left join resolved_manual rm
    on ir.provided_evidence_event_id is null
   and ir.project_id = rm.project_id
   and ir.source_batch_id = rm.source_batch_id
)
insert into public.project_facts (
  project_id,
  as_of_at,
  observed_at,
  fact_kind,
  fact_payload,
  interaction_id,
  evidence_event_id,
  source_span_id,
  source_char_start,
  source_char_end
)
select
  rr.project_id,
  rr.as_of_at,
  rr.observed_at,
  rr.fact_kind,
  rr.fact_payload,
  rr.interaction_id,
  rr.evidence_event_id,
  rr.source_span_id,
  rr.source_char_start,
  rr.source_char_end
from resolved_rows rr
where rr.evidence_event_id is not null
  and not exists (
    select 1
    from public.project_facts pf
    where pf.project_id = rr.project_id
      and pf.as_of_at = rr.as_of_at
      and pf.observed_at = rr.observed_at
      and pf.fact_kind = rr.fact_kind
      and pf.fact_payload = rr.fact_payload
      and pf.evidence_event_id is not distinct from rr.evidence_event_id
      and pf.interaction_id is not distinct from rr.interaction_id
      and pf.source_span_id is not distinct from rr.source_span_id
      and pf.source_char_start is not distinct from rr.source_char_start
      and pf.source_char_end is not distinct from rr.source_char_end
  )
order by rr.line_no;

commit;
`;
}

async function main(): Promise<void> {
  const options = parseArgs(Deno.args);
  const inputText = await Deno.readTextFile(options.inputPath);
  const rows = parseInputRows(options, inputText);
  validateManualGroupConsistency(rows);

  const sql = buildSql(options, rows);
  await Deno.writeTextFile(options.outputPath, sql);

  const summary = buildSummary(rows);
  const summaryText = formatSummary(summary);

  if (options.summaryOutPath) {
    await Deno.writeTextFile(options.summaryOutPath, `${summaryText}\n`);
  }

  console.log(summaryText);
  console.log(`sql_output: ${options.outputPath}`);
  if (options.summaryOutPath) {
    console.log(`summary_output: ${options.summaryOutPath}`);
  }
}

if (import.meta.main) {
  main();
}
