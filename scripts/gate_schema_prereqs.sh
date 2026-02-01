#!/usr/bin/env bash
set -euo pipefail

# scripts/gate_schema_prereqs.sh
#
# Drift-proofing: verify required tables/columns exist BEFORE running invariant gates.
# Prints exactly one line:
#   PREREQS|PASS|missing=0
# or
#   PREREQS|FAIL|missing=N|details=...
#
# Requires:
#   DATABASE_URL
# Optional:
#   REQUIRE_LOAD_ENV=true  (if set, will source scripts/load-env.sh and run scripts/test-credentials.sh)

usage() {
  cat <<'USAGE'
Usage: ./scripts/gate_schema_prereqs.sh [--ci]
Env: DATABASE_URL
Opt env: REQUIRE_LOAD_ENV=true
Stdout: PREREQS|PASS/FAIL|...
Exit: 0 pass, 1 fail, 10 config
USAGE
}

CI=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ci) CI=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 10 ;;
  esac
done

: "${DATABASE_URL:?DATABASE_URL required}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ "${REQUIRE_LOAD_ENV:-}" == "true" && -n "$REPO_ROOT" ]]; then
  # Canon auth pattern (per STRAT) when used in CI.
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/load-env.sh"
  "${REPO_ROOT}/scripts/test-credentials.sh" >/dev/null
fi

need_bin(){ command -v "$1" >/dev/null 2>&1; }
need_bin psql || { echo "PREREQS|FAIL|missing=1|details=missing_bin:psql"; exit 10; }
need_bin jq || { echo "PREREQS|FAIL|missing=1|details=missing_bin:jq"; exit 10; }

REQ_SQL=$(cat <<'SQL'
with required as (
  select * from (values
    ('public','calls_raw','interaction_id'),
    ('public','calls_raw','transcript'),
    ('public','conversation_spans','id'),
    ('public','conversation_spans','interaction_id'),
    ('public','conversation_spans','span_index'),
    ('public','conversation_spans','char_start'),
    ('public','conversation_spans','char_end'),
    ('public','conversation_spans','is_superseded'),
    ('public','review_queue','span_id'),
    ('public','review_queue','status'),
    ('public','span_attributions','span_id'),
    ('public','span_attributions','needs_review')
  ) as t(table_schema, table_name, column_name)
),
present as (
  select c.table_schema, c.table_name, c.column_name
  from information_schema.columns c
  join required r
    on r.table_schema=c.table_schema
   and r.table_name=c.table_name
   and r.column_name=c.column_name
),
missing as (
  select r.*
  from required r
  left join present p
    on p.table_schema=r.table_schema
   and p.table_name=r.table_name
   and p.column_name=r.column_name
  where p.column_name is null
)
select json_build_object(
  'missing_count', (select count(*) from missing),
  'missing', coalesce(json_agg(json_build_object('table', table_name, 'column', column_name) order by table_name, column_name), '[]'::json)
) as payload
from missing;
SQL
)

payload="$(psql -t -A -v ON_ERROR_STOP=1 -c "$REQ_SQL" "$DATABASE_URL" 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  echo "PREREQS|FAIL|missing=1|details=db_query_failed"
  exit 1
fi

missing_count="$(echo "$payload" | jq -r '.missing_count' 2>/dev/null || echo "")"
if [[ -z "$missing_count" || "$missing_count" == "null" ]]; then
  echo "PREREQS|FAIL|missing=1|details=bad_payload"
  exit 1
fi

if [[ "$missing_count" -eq 0 ]]; then
  echo "PREREQS|PASS|missing=0"
  exit 0
fi

details="$(echo "$payload" | jq -c '.missing' | head -c 240)"
echo "PREREQS|FAIL|missing=${missing_count}|details=${details}"
exit 1
