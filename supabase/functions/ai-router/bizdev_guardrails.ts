type Decision = "assign" | "review" | "none";

export type BizDevCallType = "bizdev_prospect_intake" | "project_execution";
export type BizDevConfidence = "high" | "medium" | "low";

export interface BizDevClassification {
  call_type: BizDevCallType;
  confidence: BizDevConfidence;
  evidence_tags: string[];
  commitment_to_start: boolean;
  commitment_tags: string[];
}

export interface BizDevCommitmentGateInput {
  transcript: string;
  decision: Decision;
  project_id: string | null;
}

export interface BizDevCommitmentGateResult {
  decision: Decision;
  project_id: string | null;
  classification: BizDevClassification;
  downgraded: boolean;
  reason: string | null;
}

const BIZDEV_PATTERNS: RegExp[] = [
  /\binitial stage(?:s)?\b/g,
  /\blooking to\b/g,
  /\blooking at\b/g,
  /\bexploring\b/g,
  /\bthinking about\b/g,
  /\bquote\b/g,
  /\bestimate\b/g,
  /\bbid\b/g,
  /\bproposal\b/g,
  /\bprospect\b/g,
  /\bschedule (?:a )?(?:meeting|visit|walkthrough|you in)\b/g,
  /\btext me\b/g,
  /\bshoot me a text\b/g,
  /\bsend me (?:your )?(?:name|address|contact)\b/g,
  /\bnew (?:lead|project)\b/g,
];

const COMMITMENT_PATTERNS: RegExp[] = [
  /\bsigned (?:the )?contract\b/g,
  /\bcontract (?:is )?signed\b/g,
  /\bdeposit (?:paid|received|sent)\b/g,
  /\bdown payment\b/g,
  /\bpermit(?:s)? (?:approved|pulled|issued|in hand)\b/g,
  /\bpurchase order\b/g,
  /\bpo\b/g,
  /\bstart date\b/g,
  /\bwe (?:can|will) start\b/g,
  /\bkickoff\b/g,
  /\bcrew starts?\b/g,
  /\bmobiliz(?:e|ation)\b/g,
];

function normalize(text: string): string {
  return (text || "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\u2018\u2019\u201C\u201D`"]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function extractPatternHits(text: string, patterns: RegExp[]): string[] {
  const out: string[] = [];
  for (const pattern of patterns) {
    const matches = text.matchAll(pattern);
    for (const match of matches) {
      const term = (match[0] || "").trim();
      if (term && !out.includes(term)) out.push(term);
    }
  }
  return out;
}

export function classifyBizDevProspect(transcript: string): BizDevClassification {
  const normalized = normalize(transcript);
  const evidence_tags = extractPatternHits(normalized, BIZDEV_PATTERNS);
  const commitment_tags = extractPatternHits(normalized, COMMITMENT_PATTERNS);

  let confidence: BizDevConfidence = "low";
  if (evidence_tags.length >= 2) confidence = "high";
  else if (evidence_tags.length >= 1) confidence = "medium";

  return {
    call_type: evidence_tags.length > 0 ? "bizdev_prospect_intake" : "project_execution",
    confidence,
    evidence_tags,
    commitment_to_start: commitment_tags.length > 0,
    commitment_tags,
  };
}

export function applyBizDevCommitmentGate(
  input: BizDevCommitmentGateInput,
): BizDevCommitmentGateResult {
  const classification = classifyBizDevProspect(input.transcript);
  const mustGate = classification.call_type === "bizdev_prospect_intake" && !classification.commitment_to_start;

  if (!mustGate) {
    return {
      decision: input.decision,
      project_id: input.project_id,
      classification,
      downgraded: false,
      reason: null,
    };
  }

  return {
    decision: input.decision === "none" ? "none" : "review",
    project_id: null,
    classification,
    downgraded: input.project_id !== null || input.decision === "assign",
    reason: "bizdev_without_commitment",
  };
}
