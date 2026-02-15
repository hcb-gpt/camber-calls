export function homeownerOverrideActsAsStrongAnchor(meta: Record<string, any> | null | undefined): boolean {
  const override = meta?.homeowner_override === true;
  const conflictProjectId = typeof meta?.homeowner_override_conflict_project_id === "string" &&
    meta.homeowner_override_conflict_project_id.trim().length > 0;
  const conflictTerm = typeof meta?.homeowner_override_conflict_term === "string" &&
    meta.homeowner_override_conflict_term.trim().length > 0;
  return override && !conflictProjectId && !conflictTerm;
}
