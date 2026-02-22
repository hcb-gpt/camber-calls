#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/consolidation_dataset_probe.sh [options]

Read-only consolidation dataset probe:
- Picks a candidate run with non-zero extraction signal
- Finds a baseline run for the same call when available
- Computes row deltas on module_* tables when those surfaces exist

Options:
  --lookback-hours N   Window for candidate search (default: 72)
  --limit N            Candidate pool size (default: 25)
  --min-claims N       Minimum extracted/claim rows (default: 1)
  --run-id UUID        Force candidate run_id instead of auto-pick
  --help               Show this message
EOF
}

LOOKBACK_HOURS=72
LIMIT=25
MIN_CLAIMS=1
FORCED_RUN_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lookback-hours)
      LOOKBACK_HOURS="${2:-}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:-}"
      shift 2
      ;;
    --min-claims)
      MIN_CLAIMS="${2:-}"
      shift 2
      ;;
    --run-id)
      FORCED_RUN_ID="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! [[ "${LOOKBACK_HOURS}" =~ ^[0-9]+$ && "${LIMIT}" =~ ^[0-9]+$ && "${MIN_CLAIMS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: numeric arguments required for --lookback-hours, --limit, --min-claims." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

PSQL_BIN="${PSQL_PATH:-psql}"
if ! command -v "${PSQL_BIN}" >/dev/null 2>&1; then
  echo "ERROR: psql not found (set PSQL_PATH or add to PATH)." >&2
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is not set." >&2
  exit 1
fi

run_sql() {
  local sql="$1"
  "${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -P pager=off -At -F $'\t' -c "${sql}"
}

find_candidate_sql=$(cat <<EOF
WITH claim_counts AS (
  SELECT jc.run_id, COUNT(*)::int AS claim_rows
  FROM public.journal_claims jc
  GROUP BY jc.run_id
),
loop_counts AS (
  SELECT jol.run_id,
         COUNT(*) FILTER (WHERE jol.status = 'open')::int AS open_loop_rows
  FROM public.journal_open_loops jol
  GROUP BY jol.run_id
),
review_counts AS (
  SELECT jrq.run_id,
         COUNT(*) FILTER (WHERE jrq.status = 'pending')::int AS pending_review_rows
  FROM public.journal_review_queue jrq
  GROUP BY jrq.run_id
),
recent AS (
  SELECT
    jr.run_id::text,
    jr.call_id,
    COALESCE(cc.claim_rows, 0) AS claim_rows,
    COALESCE(jr.claims_extracted, 0) AS claims_extracted,
    COALESCE(lc.open_loop_rows, 0) AS open_loop_rows,
    COALESCE(rc.pending_review_rows, 0) AS pending_review_rows,
    jr.started_at
  FROM public.journal_runs jr
  LEFT JOIN claim_counts cc ON cc.run_id = jr.run_id
  LEFT JOIN loop_counts lc ON lc.run_id = jr.run_id
  LEFT JOIN review_counts rc ON rc.run_id = jr.run_id
  WHERE jr.started_at >= (now() - make_interval(hours => ${LOOKBACK_HOURS}))
    AND jr.status = 'success'
),
scored AS (
  SELECT *
  FROM recent
  WHERE GREATEST(claim_rows, claims_extracted) >= ${MIN_CLAIMS}
  ORDER BY GREATEST(claim_rows, claims_extracted) DESC, started_at DESC
  LIMIT ${LIMIT}
)
SELECT run_id, call_id, claim_rows, claims_extracted, open_loop_rows, pending_review_rows
FROM scored
ORDER BY GREATEST(claim_rows, claims_extracted) DESC, started_at DESC
LIMIT 1;
EOF
)

if [[ -n "${FORCED_RUN_ID}" ]]; then
  candidate_row="$(run_sql "SELECT run_id::text, call_id, 0, 0, 0, 0 FROM public.journal_runs WHERE run_id = '${FORCED_RUN_ID}'::uuid LIMIT 1;")"
else
  candidate_row="$(run_sql "${find_candidate_sql}")"
fi

if [[ -z "${candidate_row}" ]]; then
  echo "PROBE_RESULT=NO_CANDIDATE lookback_hours=${LOOKBACK_HOURS} min_claims=${MIN_CLAIMS}"
  exit 0
fi

IFS=$'\t' read -r candidate_run_id candidate_call_id candidate_claim_rows candidate_claims_extracted candidate_open_loops candidate_pending_reviews <<<"${candidate_row}"

if [[ -z "${candidate_run_id}" || -z "${candidate_call_id}" ]]; then
  echo "ERROR: could not parse candidate run row." >&2
  exit 1
fi

baseline_row="$(
  run_sql "
    SELECT jr.run_id::text
    FROM public.journal_runs jr
    WHERE jr.call_id = '${candidate_call_id}'
      AND jr.run_id <> '${candidate_run_id}'::uuid
      AND jr.status = 'success'
    ORDER BY jr.started_at DESC
    LIMIT 1;
  "
)"
baseline_run_id="${baseline_row:-}"

echo "CANDIDATE_RUN_ID=${candidate_run_id}"
echo "CANDIDATE_CALL_ID=${candidate_call_id}"
echo "CANDIDATE_SIGNAL claim_rows=${candidate_claim_rows} claims_extracted=${candidate_claims_extracted} open_loops=${candidate_open_loops} pending_reviews=${candidate_pending_reviews}"
if [[ -n "${baseline_run_id}" ]]; then
  echo "BASELINE_RUN_ID=${baseline_run_id}"
else
  echo "BASELINE_RUN_ID=NONE"
fi

table_ready() {
  local table="$1"
  local ok
  ok="$(
    run_sql "
      SELECT CASE WHEN
        to_regclass('public.${table}') IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema='public'
            AND table_name='${table}'
            AND column_name='run_id'
        )
      THEN '1' ELSE '0' END;
    "
  )"
  [[ "${ok}" == "1" ]]
}

count_for_run() {
  local table="$1"
  local run_id="$2"
  run_sql "SELECT COUNT(*)::bigint FROM public.${table} WHERE run_id = '${run_id}'::uuid;"
}

surface_summary() {
  local table="$1"
  if ! table_ready "${table}"; then
    echo "SURFACE ${table} status=missing_or_no_run_id baseline=NA candidate=NA delta=NA"
    return 0
  fi

  local candidate_count
  local baseline_count
  local delta

  candidate_count="$(count_for_run "${table}" "${candidate_run_id}")"
  if [[ -n "${baseline_run_id}" ]]; then
    baseline_count="$(count_for_run "${table}" "${baseline_run_id}")"
  else
    baseline_count="0"
  fi
  delta=$((candidate_count - baseline_count))

  echo "SURFACE ${table} status=ok baseline=${baseline_count} candidate=${candidate_count} delta=${delta}"
}

surface_summary "module_claims"
surface_summary "module_promotions"
surface_summary "module_receipts"

v_module_health_exists="$(run_sql "SELECT CASE WHEN to_regclass('public.v_module_health') IS NOT NULL THEN '1' ELSE '0' END;")"
if [[ "${v_module_health_exists}" == "1" ]]; then
  vmh_count="$(run_sql "SELECT COUNT(*)::bigint FROM public.v_module_health;")"
  echo "SURFACE v_module_health status=ok rows=${vmh_count}"
else
  echo "SURFACE v_module_health status=missing rows=NA"
fi

echo "PROBE_RESULT=OK candidate_run_id=${candidate_run_id} baseline_run_id=${baseline_run_id:-NONE}"
