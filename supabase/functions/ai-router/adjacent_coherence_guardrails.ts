const SWITCH_SIGNAL_PATTERNS: RegExp[] = [
  /\banother\s+(?:project|job|house|site|one)\b/i,
  /\bdifferent\s+(?:project|job|house|site|one)\b/i,
  /\bother\s+(?:project|job|house|site)\b/i,
  /\bswitch(?:ing)?\s+(?:to|over|back)\b/i,
  /\bmove(?:d|ing)?\s+(?:to|over to)\b/i,
  /\bseparate\s+(?:project|job|site)\b/i,
  /\bnew\s+project\b/i,
  /\bnext\s+project\b/i,
  /\bon\s+the\s+other\s+job\b/i,
];

export interface AdjacentCoherenceResult {
  enforced: boolean;
  baseline_project_id: string | null;
  override_project_id: string | null;
  downgrade_to_review: boolean;
  reason: string | null;
}

export function hasSwitchSignal(transcript: string): boolean {
  const text = String(transcript || "");
  if (!text) return false;
  return SWITCH_SIGNAL_PATTERNS.some((re) => re.test(text));
}

export function evaluateAdjacentSpanCoherence(input: {
  span_index: number;
  transcript_text: string;
  current_project_id: string | null;
  prior_assigned_project_ids: string[];
  candidate_project_ids: string[];
}): AdjacentCoherenceResult {
  const spanIndex = Number(input.span_index);
  const currentProjectId = input.current_project_id || null;
  const prior = (input.prior_assigned_project_ids || []).filter(Boolean);
  const candidateIds = new Set((input.candidate_project_ids || []).filter(Boolean));

  if (!currentProjectId || Number.isNaN(spanIndex) || spanIndex < 1 || spanIndex > 3) {
    return {
      enforced: false,
      baseline_project_id: null,
      override_project_id: null,
      downgrade_to_review: false,
      reason: null,
    };
  }

  if (prior.length === 0) {
    return {
      enforced: false,
      baseline_project_id: null,
      override_project_id: null,
      downgrade_to_review: false,
      reason: null,
    };
  }

  const counts = new Map<string, number>();
  for (const pid of prior) {
    counts.set(pid, (counts.get(pid) || 0) + 1);
  }
  if (counts.size !== 1) {
    return {
      enforced: false,
      baseline_project_id: null,
      override_project_id: null,
      downgrade_to_review: false,
      reason: null,
    };
  }

  const baselineProjectId = prior[0];
  if (currentProjectId === baselineProjectId) {
    return {
      enforced: false,
      baseline_project_id: baselineProjectId,
      override_project_id: null,
      downgrade_to_review: false,
      reason: null,
    };
  }

  if (hasSwitchSignal(input.transcript_text)) {
    return {
      enforced: false,
      baseline_project_id: baselineProjectId,
      override_project_id: null,
      downgrade_to_review: false,
      reason: null,
    };
  }

  if (candidateIds.has(baselineProjectId)) {
    return {
      enforced: true,
      baseline_project_id: baselineProjectId,
      override_project_id: baselineProjectId,
      downgrade_to_review: false,
      reason: "adjacent_span_coherence_override",
    };
  }

  return {
    enforced: true,
    baseline_project_id: baselineProjectId,
    override_project_id: null,
    downgrade_to_review: true,
    reason: "adjacent_span_coherence_needs_review",
  };
}
