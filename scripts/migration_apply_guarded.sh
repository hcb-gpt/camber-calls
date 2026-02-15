#!/usr/bin/env bash
set -euo pipefail

# migration_apply_guarded.sh
# Write-mode Supabase migration wrapper with claim/session guard.
#
# Allowed commands:
#   migration up ...
#   migration repair ...
#   db push ...
#
# Required env:
#   ORIGIN_SESSION
#   CLAIM_RECEIPT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/claim_guard.sh"

usage() {
  cat <<'EOF' 1>&2
Usage:
  scripts/migration_apply_guarded.sh migration up --linked --yes [--include-all]
  scripts/migration_apply_guarded.sh migration repair <version> --status applied|reverted [--linked]
  scripts/migration_apply_guarded.sh db push --linked [--include-all]

Required env:
  ORIGIN_SESSION
  CLAIM_RECEIPT (must begin with claim__)

Optional env:
  MIGRATION_GUARD_ARTIFACT_ROOT (default: artifacts/migration_apply_guarded)
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

require_claim_context "migration_apply_guarded.sh" || exit 2

if ! command -v supabase >/dev/null 2>&1; then
  echo "ERROR: supabase CLI not found in PATH." >&2
  exit 2
fi

CMD_1="$1"
CMD_2="$2"
case "${CMD_1} ${CMD_2}" in
  "migration up"|"migration repair"|"db push")
    ;;
  *)
    echo "ERROR: unsupported command '${CMD_1} ${CMD_2}'." >&2
    usage
    ;;
esac

RUN_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARTIFACT_ROOT="${MIGRATION_GUARD_ARTIFACT_ROOT:-artifacts/migration_apply_guarded}"
ARTIFACT_DIR="${ARTIFACT_ROOT}/${RUN_STAMP}"
mkdir -p "${ARTIFACT_DIR}"
write_claim_artifact "${ARTIFACT_DIR}" "migration_apply_guarded.sh" "migration_write"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "origin_session=${ORIGIN_SESSION}"
  echo "claim_receipt=${CLAIM_RECEIPT}"
  echo "command=supabase $*"
} > "${ARTIFACT_DIR}/command_context.txt"

echo "Running guarded command: supabase $*"
echo "Artifacts: ${ARTIFACT_DIR}/"

supabase "$@" 2>&1 | tee "${ARTIFACT_DIR}/command_output.log"
