#!/usr/bin/env bash
# deploy-vs-default.sh - Verify deployed functions match default branch
# REQUIRED: Run after every merge to verify alignment
#
# Usage:
#   ./scripts/deploy-vs-default.sh
#
# Output:
#   ALL OK: deploy_vs_default | functions=N | migrations=M | headSHA=<sha>
#   or
#   DRIFT: deploy_vs_default | drifted=<list> | headSHA=<sha>
#
# Exit codes:
#   0 = ALL OK
#   1 = DRIFT detected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load credentials
# shellcheck source=load-env.sh
source "${SCRIPT_DIR}/load-env.sh" 2>/dev/null || true

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Get default branch
cd "$REPO_ROOT"
git fetch origin --quiet 2>/dev/null || true
DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo 'master')"
HEAD_SHA="$(git rev-parse --short HEAD)"
ORIGIN_SHA="$(git rev-parse --short origin/${DEFAULT_BRANCH})"

# List of deployed edge functions to check
DEPLOYED_FUNCTIONS=(
  "process-call"
  "segment-call"
  "segment-llm"
  "context-assembly"
  "ai-router"
  "admin-reseed"
)

drifted=()
aligned=0

echo "Checking deployed functions vs origin/${DEFAULT_BRANCH}..."

for fn in "${DEPLOYED_FUNCTIONS[@]}"; do
  fn_path="supabase/functions/${fn}/index.ts"

  if [[ ! -f "${REPO_ROOT}/${fn_path}" ]]; then
    # Function doesn't exist in repo
    drifted+=("${fn}:missing_in_repo")
    continue
  fi

  # Check if function exists on default branch
  if git show "origin/${DEFAULT_BRANCH}:${fn_path}" >/dev/null 2>&1; then
    # Compare local HEAD vs origin default
    local_hash="$(git hash-object "${REPO_ROOT}/${fn_path}")"
    origin_hash="$(git show "origin/${DEFAULT_BRANCH}:${fn_path}" 2>/dev/null | git hash-object --stdin)"

    if [[ "$local_hash" == "$origin_hash" ]]; then
      aligned=$((aligned + 1))
    else
      drifted+=("${fn}:content_differs")
    fi
  else
    # Function exists locally but not on default branch yet
    drifted+=("${fn}:not_in_default")
  fi
done

# Check migration count alignment
migrations_local="$(find "${REPO_ROOT}/supabase/migrations" -name "*.sql" 2>/dev/null | wc -l | tr -d ' ')"
migrations_origin="$(git ls-tree -r --name-only "origin/${DEFAULT_BRANCH}" -- supabase/migrations/ 2>/dev/null | grep -c '\.sql$' || echo 0)"

# Build output
if [[ ${#drifted[@]} -eq 0 && "$migrations_local" == "$migrations_origin" ]]; then
  echo "ALL OK: deploy_vs_default | functions=${aligned}/${#DEPLOYED_FUNCTIONS[@]} | migrations=${migrations_local} | headSHA=${HEAD_SHA} | originSHA=${ORIGIN_SHA} | ts=${TS}"
  exit 0
else
  drift_str=""
  if [[ ${#drifted[@]} -gt 0 ]]; then
    drift_str="functions=$(IFS=','; echo "${drifted[*]}")"
  fi
  if [[ "$migrations_local" != "$migrations_origin" ]]; then
    drift_str="${drift_str}${drift_str:+,}migrations_local=${migrations_local}_vs_origin=${migrations_origin}"
  fi
  echo "DRIFT: deploy_vs_default | ${drift_str} | headSHA=${HEAD_SHA} | originSHA=${ORIGIN_SHA} | ts=${TS}"
  exit 1
fi
