#!/usr/bin/env bash
set -euo pipefail

# spotcheck_queue.sh
#
# Runs scripts/spotcheck_queue.sql against one interaction_id and saves output.
#
# Usage:
#   ./scripts/spotcheck_queue.sh <interaction_id>
#   ./scripts/spotcheck_queue.sh --pick-latest
#   ./scripts/spotcheck_queue.sh --pick-latest --out-dir /tmp/spotcheck_queue

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

PSQL_BIN="${PSQL_PATH:-psql}"
if [[ ! -x "${PSQL_BIN}" ]]; then
  if command -v "${PSQL_BIN}" >/dev/null 2>&1; then
    PSQL_BIN="$(command -v "${PSQL_BIN}")"
  else
    echo "ERROR: psql not found. Set PSQL_PATH or install psql." >&2
    exit 1
  fi
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set after env load." >&2
  exit 1
fi

IID=""
PICK_LATEST=false
OUT_DIR="${ROOT_DIR}/artifacts/spotcheck_queue"

sql_scalar() {
  local sql="$1"
  "${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -At -c "${sql}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pick-latest)
      PICK_LATEST=true
      shift
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      if [[ -z "${OUT_DIR}" ]]; then
        echo "ERROR: --out-dir requires a path." >&2
        exit 1
      fi
      shift 2
      ;;
    --help|-h)
      echo "Usage:"
      echo "  $0 <interaction_id>"
      echo "  $0 --pick-latest"
      echo "  $0 --pick-latest --out-dir /tmp/spotcheck_queue"
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      if [[ -n "${IID}" ]]; then
        echo "ERROR: multiple interaction IDs provided." >&2
        exit 1
      fi
      IID="$1"
      shift
      ;;
  esac
done

if [[ "${PICK_LATEST}" == "true" && -n "${IID}" ]]; then
  echo "ERROR: use either <interaction_id> or --pick-latest, not both." >&2
  exit 1
fi

if [[ "${PICK_LATEST}" == "true" ]]; then
  IID="$(sql_scalar "SELECT interaction_id FROM calls_raw WHERE coalesce(is_shadow,false)=false ORDER BY ingested_at_utc DESC NULLS LAST LIMIT 1;")"
fi

if [[ -z "${IID}" ]]; then
  echo "ERROR: no interaction_id resolved." >&2
  exit 1
fi

if [[ ! "${IID}" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "ERROR: interaction_id has unsupported characters." >&2
  exit 1
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${OUT_DIR}/${TS}_${IID}"
mkdir -p "${RUN_DIR}"

OUT_FILE="${RUN_DIR}/spotcheck_queue.txt"
SQL_FILE="${ROOT_DIR}/scripts/spotcheck_queue.sql"

"${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -v interaction_id="${IID}" -f "${SQL_FILE}" | tee "${OUT_FILE}"

echo "SPOTCHECK_QUEUE_READY"
echo "interaction_id=${IID}"
echo "run_dir=${RUN_DIR}"
echo "out=${OUT_FILE}"

