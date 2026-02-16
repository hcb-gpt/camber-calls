#!/usr/bin/env bash

# Shared preflight for write-mode scripts.
# Enforces explicit ownership context to reduce DB write collisions.

require_claim_context() {
  local script_name="${1:-write_script}"
  local missing=()

  if [[ -z "${ORIGIN_SESSION:-}" ]]; then
    missing+=("ORIGIN_SESSION")
  fi
  if [[ -z "${CLAIM_RECEIPT:-}" ]]; then
    missing+=("CLAIM_RECEIPT")
  fi

  if (( ${#missing[@]} > 0 )); then
    echo "ERROR: ${script_name} is write-mode and requires ${missing[*]}." >&2
    echo "Set and retry, for example:" >&2
    echo "  export ORIGIN_SESSION=dev-3" >&2
    echo "  export CLAIM_RECEIPT=claim__dev-3__..." >&2
    return 2
  fi

  if [[ "${CLAIM_RECEIPT}" != claim__* ]]; then
    echo "ERROR: CLAIM_RECEIPT must begin with 'claim__' (got: ${CLAIM_RECEIPT})." >&2
    return 2
  fi

  return 0
}

write_claim_artifact() {
  local artifact_dir="$1"
  local script_name="${2:-write_script}"
  local mode="${3:-write_mode}"

  mkdir -p "${artifact_dir}"
  cat > "${artifact_dir}/claim_context.txt" <<EOF
timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
script=${script_name}
mode=${mode}
origin_session=${ORIGIN_SESSION:-}
claim_receipt=${CLAIM_RECEIPT:-}
claim_eta_min=${CLAIM_ETA_MIN:-}
claim_lease_min=${CLAIM_LEASE_MIN:-}
claim_resource=${CLAIM_RESOURCE:-}
EOF
}
