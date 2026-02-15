#!/usr/bin/env bash
set -euo pipefail

# Canonical read-only SQL path for DATA/DEV sessions.
# Usage:
#   scripts/query.sh "select now();"
#   scripts/query.sh --file scripts/daily_digest.sql

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set after loading env." >&2
  exit 1
fi

PSQL_BIN="${PSQL_PATH:-psql}"
if [[ "${PSQL_BIN}" == */* ]]; then
  if [[ ! -x "${PSQL_BIN}" ]]; then
    echo "ERROR: psql not executable at PSQL_PATH=${PSQL_BIN}" >&2
    exit 1
  fi
else
  if ! command -v "${PSQL_BIN}" >/dev/null 2>&1; then
    echo "ERROR: psql not found in PATH (or set PSQL_PATH)." >&2
    exit 1
  fi
fi

run_sql() {
  local sql="$1"
  local upper
  upper="$(printf '%s' "${sql}" | tr '[:lower:]' '[:upper:]')"

  # Guard: read-only entry points only.
  if [[ ! "${upper}" =~ ^[[:space:]]*(SELECT|WITH|EXPLAIN|SHOW) ]]; then
    echo "ERROR: only read-only statements are allowed (SELECT/WITH/EXPLAIN/SHOW)." >&2
    exit 1
  fi

  # Avoid false positives on identifiers like `created_at` by matching whole tokens only.
  # Note: this is not a SQL parser; keywords inside string literals may still trip the guard.
  local mutating_re
  mutating_re='(^|[^A-Z0-9_])(INSERT|UPDATE|DELETE|UPSERT|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE)($|[^A-Z0-9_])'
  if [[ "${upper}" =~ ${mutating_re} ]]; then
    echo "ERROR: mutating SQL detected; query.sh is read-only." >&2
    exit 1
  fi

  "${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -P pager=off -c "${sql}"
}

if [[ "${1:-}" == "--file" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "Usage: scripts/query.sh --file <sql_file>" >&2
    exit 1
  fi
  if [[ ! -f "${2}" ]]; then
    echo "ERROR: SQL file not found: ${2}" >&2
    exit 1
  fi
  run_sql "$(cat "${2}")"
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: scripts/query.sh \"select ...\" | --file <sql_file>" >&2
  exit 1
fi

run_sql "$1"
