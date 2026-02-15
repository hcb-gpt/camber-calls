export const AUTO_RESEGMENT_MAX_SPAN_CHARS = 3000;

const STRONG_ANCHOR_TYPES = new Set([
  "exact_project_name",
  "alias",
  "address_fragment",
  "client_name",
]);

export interface GuardrailAnchor {
  match_type: string;
  candidate_project_id: string | null;
}

export interface AutoResegmentInvariantResult {
  triggered: boolean;
  reasons: string[];
  span_chars: number;
  strong_anchor_project_count: number;
}

export function countStrongAnchorProjects(anchors: GuardrailAnchor[]): number {
  const projectIds = new Set<string>();
  for (const anchor of anchors || []) {
    if (!STRONG_ANCHOR_TYPES.has(String(anchor?.match_type || ""))) continue;
    const pid = String(anchor?.candidate_project_id || "").trim();
    if (!pid) continue;
    projectIds.add(pid);
  }
  return projectIds.size;
}

export function evaluateAutoResegmentInvariant(input: {
  span_chars: number;
  anchors: GuardrailAnchor[];
  additional_strong_project_ids?: string[];
}): AutoResegmentInvariantResult {
  const reasons: string[] = [];
  const spanChars = Number(input?.span_chars || 0);
  const projectIds = new Set<string>();
  for (const anchor of input?.anchors || []) {
    if (!STRONG_ANCHOR_TYPES.has(String(anchor?.match_type || ""))) continue;
    const pid = String(anchor?.candidate_project_id || "").trim();
    if (!pid) continue;
    projectIds.add(pid);
  }
  for (const pid of input?.additional_strong_project_ids || []) {
    const normalized = String(pid || "").trim();
    if (!normalized) continue;
    projectIds.add(normalized);
  }
  const strongAnchorProjectCount = projectIds.size;

  if (spanChars > AUTO_RESEGMENT_MAX_SPAN_CHARS) {
    reasons.push("span_chars_over_3000");
  }
  if (strongAnchorProjectCount > 1) {
    reasons.push("multiple_strong_anchor_projects");
  }

  return {
    triggered: reasons.length > 0,
    reasons,
    span_chars: spanChars,
    strong_anchor_project_count: strongAnchorProjectCount,
  };
}
