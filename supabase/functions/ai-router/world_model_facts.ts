export interface ProjectFactRow {
  project_id: string;
  as_of_at: string;
  observed_at: string;
  fact_kind: string;
  fact_payload: unknown;
  evidence_event_id: string | null;
  interaction_id: string | null;
}

export interface ProjectFactsPack {
  project_id: string;
  facts: ProjectFactRow[];
}

export interface WorldModelReference {
  project_id: string;
  fact_kind: string;
  fact_as_of_at: string | null;
  fact_excerpt: string;
  relevance: string;
}

export interface WorldModelGuardrailInput {
  decision: "assign" | "review" | "none";
  project_id: string | null;
  transcript: string;
  world_model_references: WorldModelReference[];
  project_facts: ProjectFactsPack[];
}

export interface WorldModelGuardrailResult {
  decision: "assign" | "review" | "none";
  downgraded: boolean;
  reason_code: string | null;
  world_model_references: WorldModelReference[];
  strong_anchor_present: boolean;
  contradiction_found: boolean;
}

const STRONG_FACT_KIND_TOKENS = [
  "address",
  "alias",
  "client",
  "scope",
  "material",
  "finish",
  "feature",
  "model",
  "serial",
  "room",
  "lot",
  "unit",
];

const LOW_SIGNAL_TOKENS = new Set([
  "project",
  "house",
  "home",
  "build",
  "phase",
  "status",
  "update",
  "pending",
  "active",
  "call",
  "notes",
  "unknown",
  "none",
]);

function clamp(num: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, num));
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function truncateText(text: string, maxChars: number): string {
  if (text.length <= maxChars) return text;
  return `${text.slice(0, Math.max(0, maxChars - 3))}...`;
}

function normalizeFactString(value: unknown): string {
  if (value == null) return "";
  return String(value).replace(/\s+/g, " ").trim();
}

function compactFactPayload(payload: unknown): string {
  if (payload == null) return "none";
  if (typeof payload === "string") return truncateText(normalizeFactString(payload), 140);
  if (typeof payload === "number" || typeof payload === "boolean") return String(payload);
  if (Array.isArray(payload)) {
    const pieces = payload.map((item) => normalizeFactString(item)).filter(Boolean).slice(0, 4);
    return pieces.length > 0 ? truncateText(pieces.join("; "), 140) : "none";
  }
  if (typeof payload === "object") {
    const entries = Object.entries(payload as Record<string, unknown>)
      .filter(([key]) => key.length > 0)
      .slice(0, 5)
      .map(([key, value]) => `${key}=${normalizeFactString(value)}`);
    return entries.length > 0 ? truncateText(entries.join("; "), 160) : "none";
  }
  return truncateText(normalizeFactString(payload), 140);
}

function compactFactTextForMatching(fact: ProjectFactRow): string {
  return `${fact.fact_kind} ${compactFactPayload(fact.fact_payload)}`.toLowerCase();
}

function isAddressLike(text: string): boolean {
  return /\b\d{2,6}\s+[a-z0-9'.-]+(?:\s+[a-z0-9'.-]+){0,3}\s+(?:st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|ln|lane|ct|court|cir|circle|pl|place|way|pkwy|parkway)\b/i
    .test(text);
}

function hasStrongFactAnchor(fact: ProjectFactRow): boolean {
  const kind = (fact.fact_kind || "").toLowerCase();
  if (STRONG_FACT_KIND_TOKENS.some((token) => kind.includes(token))) return true;

  const compact = `${fact.fact_kind} ${compactFactPayload(fact.fact_payload)}`;
  if (isAddressLike(compact)) return true;

  const tokens = compact.toLowerCase().match(/[a-z0-9-]+/g) || [];
  return tokens.some((token) =>
    token.length >= 8 &&
    !LOW_SIGNAL_TOKENS.has(token) &&
    (/\d/.test(token) || token.includes("-"))
  );
}

function factContradictsTranscript(fact: ProjectFactRow, transcript: string): boolean {
  const transcriptLower = transcript.toLowerCase();
  if (!transcriptLower) return false;

  const tokens = compactFactTextForMatching(fact).match(/[a-z0-9-]+/g) || [];
  const signalTokens = tokens
    .filter((token) => token.length >= 5 && !LOW_SIGNAL_TOKENS.has(token))
    .slice(0, 5);

  for (const token of signalTokens) {
    const negationPattern = new RegExp(
      `\\b(?:not|no|never|without|isn'?t|aren'?t|wasn'?t|weren'?t)\\s+(?:\\w+\\s+){0,2}${escapeRegExp(token)}\\b`,
      "i",
    );
    if (negationPattern.test(transcriptLower)) return true;
  }

  return false;
}

export function parseBoolEnv(rawValue: string | undefined | null, defaultValue = false): boolean {
  const raw = (rawValue || "").trim().toLowerCase();
  if (!raw) return defaultValue;
  return raw === "1" || raw === "true" || raw === "yes" || raw === "y";
}

function normalizeFactRow(raw: unknown): ProjectFactRow | null {
  if (!raw || typeof raw !== "object") return null;
  const row = raw as Record<string, unknown>;
  const project_id = normalizeFactString(row.project_id);
  const as_of_at = normalizeFactString(row.as_of_at);
  const observed_at = normalizeFactString(row.observed_at);
  const fact_kind = normalizeFactString(row.fact_kind);
  if (!project_id || !as_of_at || !observed_at || !fact_kind) return null;
  return {
    project_id,
    as_of_at,
    observed_at,
    fact_kind,
    fact_payload: row.fact_payload ?? null,
    evidence_event_id: row.evidence_event_id ? normalizeFactString(row.evidence_event_id) : null,
    interaction_id: row.interaction_id ? normalizeFactString(row.interaction_id) : null,
  };
}

export function filterProjectFactsForPrompt(
  project_facts: ProjectFactsPack[] | undefined,
  opts: {
    interaction_id?: string | null;
    current_evidence_event_ids?: string[];
    max_per_project?: number;
  } = {},
): ProjectFactsPack[] {
  if (!Array.isArray(project_facts)) return [];
  const interactionId = normalizeFactString(opts.interaction_id);
  const evidenceEventIds = new Set(
    (opts.current_evidence_event_ids || []).map((id) => normalizeFactString(id)).filter(Boolean),
  );
  const maxPerProject = clamp(Number(opts.max_per_project ?? 20) || 20, 0, 50);

  const out: ProjectFactsPack[] = [];
  for (const rawPack of project_facts) {
    if (!rawPack || typeof rawPack !== "object") continue;
    const project_id = normalizeFactString(rawPack.project_id);
    if (!project_id) continue;
    const factsRaw = Array.isArray(rawPack.facts) ? rawPack.facts : [];
    const facts: ProjectFactRow[] = [];
    for (const factCandidate of factsRaw) {
      const fact = normalizeFactRow(factCandidate);
      if (!fact) continue;
      if (interactionId && fact.interaction_id && fact.interaction_id === interactionId) continue;
      if (fact.evidence_event_id && evidenceEventIds.has(fact.evidence_event_id)) continue;
      facts.push(fact);
      if (facts.length >= maxPerProject) break;
    }
    out.push({ project_id, facts });
  }
  return out;
}

export function parseWorldModelReferences(raw: unknown): WorldModelReference[] {
  if (!Array.isArray(raw)) return [];
  const refs: WorldModelReference[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    const project_id = normalizeFactString(row.project_id);
    const fact_kind = normalizeFactString(row.fact_kind);
    const fact_excerpt = truncateText(normalizeFactString(row.fact_excerpt), 180);
    const relevance = truncateText(normalizeFactString(row.relevance), 220);
    if (!project_id || !fact_kind || !fact_excerpt) continue;
    refs.push({
      project_id,
      fact_kind,
      fact_as_of_at: row.fact_as_of_at ? normalizeFactString(row.fact_as_of_at) : null,
      fact_excerpt,
      relevance: relevance || "world_model_fact_corroboration",
    });
  }
  return refs.slice(0, 8);
}

export function buildWorldModelFactsCandidateSummary(
  project_id: string,
  project_facts: ProjectFactsPack[] | undefined,
  maxFacts = 3,
): string {
  const pack = (project_facts || []).find((p) => p.project_id === project_id);
  if (!pack || !Array.isArray(pack.facts) || pack.facts.length === 0) {
    return "   - World model facts: none";
  }
  const lines = pack.facts.slice(0, clamp(maxFacts, 1, 8)).map((fact, idx) =>
    `     ${idx + 1}. [${fact.fact_kind}] as_of=${fact.as_of_at.slice(0, 10)} observed=${
      fact.observed_at.slice(0, 10)
    } fact=${compactFactPayload(fact.fact_payload)}`
  );
  return `   - World model facts (${pack.facts.length}; corroboration only):\n${lines.join("\n")}`;
}

function findMatchingFact(reference: WorldModelReference, facts: ProjectFactRow[]): ProjectFactRow | null {
  const sameKind = facts.filter((fact) => fact.fact_kind === reference.fact_kind);
  if (sameKind.length === 0) return null;

  if (reference.fact_as_of_at) {
    const exactAsOf = sameKind.find((fact) => fact.as_of_at === reference.fact_as_of_at);
    if (exactAsOf) return exactAsOf;
  }

  const refTokens = (reference.fact_excerpt.toLowerCase().match(/[a-z0-9-]+/g) || [])
    .filter((token) => token.length >= 4)
    .slice(0, 6);
  if (refTokens.length === 0) return sameKind[0];

  let best: { fact: ProjectFactRow; score: number } | null = null;
  for (const fact of sameKind) {
    const factText = compactFactTextForMatching(fact);
    const score = refTokens.filter((token) => factText.includes(token)).length;
    if (!best || score > best.score) {
      best = { fact, score };
    }
  }
  return best && best.score > 0 ? best.fact : sameKind[0];
}

export function applyWorldModelReferenceGuardrail(input: WorldModelGuardrailInput): WorldModelGuardrailResult {
  const refs = Array.isArray(input.world_model_references) ? input.world_model_references : [];
  if (!input.project_id || refs.length === 0 || input.project_facts.length === 0) {
    return {
      decision: input.decision,
      downgraded: false,
      reason_code: null,
      world_model_references: refs,
      strong_anchor_present: false,
      contradiction_found: false,
    };
  }

  const projectPack = input.project_facts.find((pack) => pack.project_id === input.project_id);
  if (!projectPack || projectPack.facts.length === 0) {
    return {
      decision: input.decision,
      downgraded: false,
      reason_code: null,
      world_model_references: [],
      strong_anchor_present: false,
      contradiction_found: false,
    };
  }

  const validatedRefs: WorldModelReference[] = [];
  const matchedFacts: ProjectFactRow[] = [];

  for (const ref of refs) {
    if (ref.project_id !== input.project_id) continue;
    const matched = findMatchingFact(ref, projectPack.facts);
    if (!matched) continue;
    validatedRefs.push(ref);
    matchedFacts.push(matched);
  }

  const strongAnchorPresent = matchedFacts.some((fact) => hasStrongFactAnchor(fact));
  const contradictionFound = matchedFacts.some((fact) => factContradictsTranscript(fact, input.transcript));

  let decision = input.decision;
  let downgraded = false;
  let reason_code: string | null = null;
  if (input.decision === "assign" && validatedRefs.length > 0 && (!strongAnchorPresent || contradictionFound)) {
    decision = "review";
    downgraded = true;
    reason_code = contradictionFound ? "world_model_fact_contradiction" : "world_model_fact_weak_only";
  }

  return {
    decision,
    downgraded,
    reason_code,
    world_model_references: validatedRefs,
    strong_anchor_present: strongAnchorPresent,
    contradiction_found: contradictionFound,
  };
}
