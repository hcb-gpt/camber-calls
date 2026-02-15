type Decision = "assign" | "review" | "none";

const BETHANY_ROAD_REGEX = /\bbethany\s+road\b/;
const WINSHIP_REGEX = /\bwinship\b/;
const STRONG_ANCHOR_TYPES = new Set(["exact_project_name", "address_fragment", "client_name"]);

export interface BethanyGuardrailAnchor {
  candidate_project_id: string | null;
  match_type: string;
  text: string;
  quote: string;
}

export interface BethanyGuardrailCandidate {
  project_id: string;
  project_name: string;
  address: string | null;
  evidence: {
    alias_matches: Array<{ term: string; match_type: string; snippet?: string }>;
  };
}

export interface BethanyGuardrailInput {
  decision: Decision;
  project_id: string | null;
  confidence: number;
  reasoning: string;
  anchors: BethanyGuardrailAnchor[];
  candidates: BethanyGuardrailCandidate[];
}

export interface BethanyGuardrailResult {
  decision: Decision;
  project_id: string | null;
  confidence: number;
  reasoning: string;
  applied: boolean;
  chosen_project_id: string | null;
  reason: string | null;
}

function normalize(text: string): string {
  return (text || "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function containsBethanyRoad(text: string): boolean {
  return BETHANY_ROAD_REGEX.test(normalize(text));
}

function isWinshipProjectName(name: string): boolean {
  return WINSHIP_REGEX.test(normalize(name));
}

function candidateHasBethanySignal(candidate: BethanyGuardrailCandidate): boolean {
  if (containsBethanyRoad(candidate.address || "")) return true;
  for (const match of candidate.evidence?.alias_matches || []) {
    if (match.match_type !== "address_fragment") continue;
    if (containsBethanyRoad(match.term || "") || containsBethanyRoad(match.snippet || "")) return true;
  }
  return false;
}

function pickWinshipCandidate(candidates: BethanyGuardrailCandidate[]): string | null {
  const winshipCandidates = candidates.filter((c) => isWinshipProjectName(c.project_name || ""));
  if (winshipCandidates.length === 0) return null;
  if (winshipCandidates.length === 1) return winshipCandidates[0].project_id;

  const withBethanyEvidence = winshipCandidates.filter(candidateHasBethanySignal);
  if (withBethanyEvidence.length === 1) return withBethanyEvidence[0].project_id;
  return null;
}

function hasConflictingStrongNonBethanyAnchor(anchors: BethanyGuardrailAnchor[], chosenProjectId: string): boolean {
  return anchors.some((anchor) => {
    if (!STRONG_ANCHOR_TYPES.has(anchor.match_type)) return false;
    if (!anchor.candidate_project_id || anchor.candidate_project_id === chosenProjectId) return false;
    if (anchor.match_type === "address_fragment") {
      const text = `${anchor.text || ""} ${anchor.quote || ""}`;
      if (containsBethanyRoad(text)) return false;
    }
    return true;
  });
}

export function applyBethanyRoadWinshipGuardrail(input: BethanyGuardrailInput): BethanyGuardrailResult {
  const bethanyAddressAnchors = (input.anchors || []).filter((anchor) =>
    anchor.match_type === "address_fragment" &&
    (containsBethanyRoad(anchor.text || "") || containsBethanyRoad(anchor.quote || ""))
  );

  if (bethanyAddressAnchors.length === 0) {
    return {
      decision: input.decision,
      project_id: input.project_id,
      confidence: input.confidence,
      reasoning: input.reasoning,
      applied: false,
      chosen_project_id: null,
      reason: "no_bethany_address_anchor",
    };
  }

  const chosenProjectId = pickWinshipCandidate(input.candidates || []);
  if (!chosenProjectId) {
    return {
      decision: input.decision,
      project_id: input.project_id,
      confidence: input.confidence,
      reasoning: input.reasoning,
      applied: false,
      chosen_project_id: null,
      reason: "winship_candidate_not_unique",
    };
  }

  if (hasConflictingStrongNonBethanyAnchor(input.anchors || [], chosenProjectId)) {
    return {
      decision: input.decision,
      project_id: input.project_id,
      confidence: input.confidence,
      reasoning: input.reasoning,
      applied: false,
      chosen_project_id: chosenProjectId,
      reason: "conflicting_strong_anchor",
    };
  }

  if (input.project_id === chosenProjectId && input.decision === "assign") {
    return {
      decision: input.decision,
      project_id: input.project_id,
      confidence: input.confidence,
      reasoning: input.reasoning,
      applied: false,
      chosen_project_id: chosenProjectId,
      reason: "already_winship_assign",
    };
  }

  return {
    decision: "assign",
    project_id: chosenProjectId,
    confidence: Math.max(input.confidence || 0, 0.8),
    reasoning: `${input.reasoning} Deterministic Bethany Road gate forced Winship assignment.`,
    applied: true,
    chosen_project_id: chosenProjectId,
    reason: "bethany_winship_forced",
  };
}
