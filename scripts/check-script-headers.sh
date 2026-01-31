#!/usr/bin/env bash
# check-script-headers.sh - Verify all scripts source load-env.sh
# REQUIRED: Run in CI to enforce credential protocol
#
# Usage:
#   ./scripts/check-script-headers.sh
#
# Checks that every .sh file in scripts/ either:
#   1. Sources load-env.sh
#   2. Is exempt (load-env.sh itself, test-credentials.sh, check-script-headers.sh)
#   3. Has # NO_CREDENTIALS_REQUIRED comment
#
# Exit codes:
#   0 = All scripts compliant
#   1 = Non-compliant scripts found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Exempt scripts (don't need credentials or are the loaders themselves)
EXEMPT_SCRIPTS=(
  "load-env.sh"
  "test-credentials.sh"
  "check-script-headers.sh"
)

is_exempt() {
  local script_name="$1"
  for exempt in "${EXEMPT_SCRIPTS[@]}"; do
    if [[ "$script_name" == "$exempt" ]]; then
      return 0
    fi
  done
  return 1
}

has_loader_source() {
  local script_path="$1"
  # Check for various ways to source load-env.sh
  grep -qE 'source.*load-env\.sh|\..*load-env\.sh' "$script_path" 2>/dev/null
}

has_no_creds_comment() {
  local script_path="$1"
  grep -q '# NO_CREDENTIALS_REQUIRED' "$script_path" 2>/dev/null
}

non_compliant=()

for script in "${SCRIPT_DIR}"/*.sh; do
  [[ -f "$script" ]] || continue

  script_name="$(basename "$script")"

  # Skip exempt scripts
  if is_exempt "$script_name"; then
    continue
  fi

  # Check for loader source or exemption comment
  if ! has_loader_source "$script" && ! has_no_creds_comment "$script"; then
    non_compliant+=("$script_name")
  fi
done

if [[ ${#non_compliant[@]} -eq 0 ]]; then
  echo "PASS: script_headers | all scripts compliant | count=$(find "${SCRIPT_DIR}" -name "*.sh" | wc -l | tr -d ' ')"
  exit 0
else
  echo "FAIL: script_headers | non_compliant=${non_compliant[*]}"
  echo ""
  echo "Fix: Add this line near the top of each non-compliant script:"
  echo '  source "$(git rev-parse --show-toplevel)/scripts/load-env.sh"'
  echo ""
  echo "Or add this comment if the script truly doesn't need credentials:"
  echo '  # NO_CREDENTIALS_REQUIRED'
  exit 1
fi
