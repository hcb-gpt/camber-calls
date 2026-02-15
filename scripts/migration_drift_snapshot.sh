#!/usr/bin/env bash
set -euo pipefail

# migration_drift_snapshot.sh
#
# Purpose:
#   Read-only drift detector between:
#     - remote: supabase_migrations.schema_migrations.version
#     - local:  supabase/migrations/<version>_*.sql filenames in git
#
# Why:
#   When remote has versions not present in git (REMOTE_ONLY), `supabase db push`
#   can fail until migration history is repaired.
#
# Usage:
#   ./scripts/migration_drift_snapshot.sh
#   ./scripts/migration_drift_snapshot.sh --suggest-repair   # prints safe repair command strings (no execution)
#
# Output contract:
#   Emits exactly one strict summary line:
#     MIGRATION_DRIFT|remote_only=N|local_only=M|remote_count=R|local_count=L
#
# Requirements:
# - `DATABASE_URL` (or credentials that set it)
# - `psql` (use `PSQL_PATH` if provided)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SUGGEST_REPAIR=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suggest-repair) SUGGEST_REPAIR=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--suggest-repair]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg '$1'" >&2
      exit 1
      ;;
  esac
done

# shellcheck source=/dev/null
if [[ -f "${ROOT_DIR}/scripts/load-env.sh" ]]; then
  source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set after env load." >&2
  exit 1
fi

PSQL_BIN="${PSQL_PATH:-psql}"
if [[ ! -x "${PSQL_BIN}" ]]; then
  if command -v "${PSQL_BIN}" >/dev/null 2>&1; then
    PSQL_BIN="$(command -v "${PSQL_BIN}")"
  else
    echo "ERROR: psql not found. Set PSQL_PATH or install psql." >&2
    exit 1
  fi
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

remote_file="${tmpdir}/remote_versions.txt"
local_file="${tmpdir}/local_versions.txt"

"${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -At -c \
  "select version from supabase_migrations.schema_migrations order by version;" \
  | sort -u > "${remote_file}"

ls -1 "${ROOT_DIR}/supabase/migrations/"*.sql 2>/dev/null \
  | xargs -n1 basename \
  | cut -d_ -f1 \
  | sort -u > "${local_file}"

remote_count="$(wc -l < "${remote_file}" | tr -d ' ')"
local_count="$(wc -l < "${local_file}" | tr -d ' ')"

remote_only_file="${tmpdir}/remote_only.txt"
local_only_file="${tmpdir}/local_only.txt"

comm -23 "${remote_file}" "${local_file}" > "${remote_only_file}"
comm -13 "${remote_file}" "${local_file}" > "${local_only_file}"

remote_only_count="$(wc -l < "${remote_only_file}" | tr -d ' ')"
local_only_count="$(wc -l < "${local_only_file}" | tr -d ' ')"

echo "MIGRATION_DRIFT|remote_only=${remote_only_count}|local_only=${local_only_count}|remote_count=${remote_count}|local_count=${local_count}"

if [[ "${remote_only_count}" -gt 0 ]]; then
  echo ""
  echo "REMOTE_ONLY (exists remotely, missing in git):"
  cat "${remote_only_file}"
fi

if [[ "${local_only_count}" -gt 0 ]]; then
  echo ""
  echo "LOCAL_ONLY (exists in git, not yet in remote history):"
  cat "${local_only_file}"
fi

if [[ "${SUGGEST_REPAIR}" == "true" && "${remote_only_count}" -gt 0 ]]; then
  echo ""
  echo "SUGGESTED REPAIR COMMANDS (NO EXECUTION):"
  echo "# Uses supabase CLI with --db-url (percent-encoded)."
  echo "# Safe: does not print DATABASE_URL value; relies on env at runtime."
  echo 'ENCODED_DB_URL="$(python3 - <<'\''PY'\''\nimport os, urllib.parse\nprint(urllib.parse.quote(os.environ[\"DATABASE_URL\"], safe=\"\"))\nPY\n)"'
  while IFS= read -r v; do
    [[ -z "${v}" ]] && continue
    echo "supabase migration repair ${v} --status reverted --db-url \"\${ENCODED_DB_URL}\""
  done < "${remote_only_file}"
fi
