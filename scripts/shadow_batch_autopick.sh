#!/usr/bin/env bash
set -euo pipefail

# REQUIRED PROTOCOL (credential loader; no exceptions)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-env.sh"

# shadow_batch_autopick.sh
# Taskpack: shadow_batch_autopick (GPT-DEV-3)
# Select candidates from DB (no spans / gap>0 / FAIL) -> run shadow batch -> emit CSV + retry list.
#
# Requires:
#   - psql (for candidate selection)
#   - shadow_batch_replay.sh in same dir by default
#
# Inputs: none (autopicks via DB); optional overrides via env.
#
# Env (optional):
#   LIMIT                default 250
#   PROOF_ROOT           default /tmp/proofs/shadow_batch
#   SKIP_IF_PASS         default 1
#   REPLAY_SCRIPT        override replay script path
#   FAIL_SOURCE          "snapshots" (default) or "none"
#
# Candidate sources (best-effort union; graceful fallback):
#   A) gap>0: v_review_coverage_gaps where review_gap > 0
#   B) no spans: calls_raw where spans_total = 0
#   C) FAIL: pipeline_scoreboard_snapshots latest status='FAIL' (if present)

# Run credential test first
"${SCRIPT_DIR}/test-credentials.sh" || exit 1

LIMIT="${LIMIT:-250}"
PROOF_ROOT="${PROOF_ROOT:-/tmp/proofs/shadow_batch}"
SKIP_IF_PASS="${SKIP_IF_PASS:-1}"
FAIL_SOURCE="${FAIL_SOURCE:-snapshots}"

REPLAY="${REPLAY_SCRIPT:-${SCRIPT_DIR}/shadow_batch_replay.sh}"

if [[ ! -x "${REPLAY}" ]]; then
  echo "error: replay script not found or not executable: ${REPLAY}" 1>&2
  exit 2
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${PROOF_ROOT}/${RUN_ID}_autopick"
mkdir -p "${RUN_DIR}"

SELECTED_IDS="${RUN_DIR}/selected_ids.txt"
RETRY_LIST="${RUN_DIR}/retry_list_failures.txt"

psql_ids() {
  local sql="$1"
  psql "${SUPABASE_DB_URL}" -X -q -A -t -v ON_ERROR_STOP=1 -c "$sql" 2>/dev/null || echo ""
}

# --- Candidate query building blocks ---

SQL_GAPS=$(cat <<SQL
select distinct interaction_id
from v_review_coverage_gaps
where review_gap > 0
order by interaction_id
limit ${LIMIT};
SQL
)

SQL_NO_SPANS=$(cat <<SQL
select distinct id as interaction_id
from calls_raw
where coalesce(spans_total, 0) = 0
order by id
limit ${LIMIT};
SQL
)

# FAIL source: snapshots (preferred when present)
SQL_FAIL_SNAPSHOTS=$(cat <<SQL
with latest as (
  select
    interaction_id,
    status,
    row_number() over (partition by interaction_id order by created_at desc) as rn
  from pipeline_scoreboard_snapshots
)
select distinct interaction_id
from latest
where rn = 1 and status = 'FAIL'
order by interaction_id
limit ${LIMIT};
SQL
)

# UNION query (best when all exist)
SQL_UNION=$(cat <<SQL
with
g as (
  select interaction_id from v_review_coverage_gaps where review_gap > 0
),
n as (
  select id as interaction_id from calls_raw where coalesce(spans_total, 0) = 0
),
f as (
  select interaction_id from (
    select interaction_id, status,
           row_number() over (partition by interaction_id order by created_at desc) rn
    from pipeline_scoreboard_snapshots
  ) s
  where rn=1 and status='FAIL'
)
select distinct interaction_id
from (
  select interaction_id from g
  union
  select interaction_id from n
  union
  select interaction_id from f
) u
order by interaction_id
limit ${LIMIT};
SQL
)

select_candidates() {
  local out_file="$1"

  # 1) Try full union (gaps + no_spans + FAIL snapshots)
  set +e
  psql_ids "$SQL_UNION" > "${out_file}.tmp"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]] || [[ ! -s "${out_file}.tmp" ]]; then
    # 2) Try gaps + no_spans union only
    local sql_gn
    sql_gn=$(cat <<SQL
with g as (
  select interaction_id from v_review_coverage_gaps where review_gap > 0
),
n as (
  select id as interaction_id from calls_raw where coalesce(spans_total, 0) = 0
)
select distinct interaction_id
from (
  select interaction_id from g
  union
  select interaction_id from n
) u
order by interaction_id
limit ${LIMIT};
SQL
)
    set +e
    psql_ids "$sql_gn" > "${out_file}.tmp"
    rc=$?
    set -e
  fi

  if [[ $rc -ne 0 ]] || [[ ! -s "${out_file}.tmp" ]]; then
    # 3) Try gaps only
    set +e
    psql_ids "$SQL_GAPS" > "${out_file}.tmp"
    rc=$?
    set -e
  fi

  if [[ $rc -ne 0 ]] || [[ ! -s "${out_file}.tmp" ]]; then
    # 4) Try no_spans only
    set +e
    psql_ids "$SQL_NO_SPANS" > "${out_file}.tmp"
    rc=$?
    set -e
  fi

  if [[ $rc -ne 0 ]] || [[ ! -s "${out_file}.tmp" ]]; then
    if [[ "${FAIL_SOURCE}" != "none" ]]; then
      # 5) Try FAIL snapshots only
      set +e
      psql_ids "$SQL_FAIL_SNAPSHOTS" > "${out_file}.tmp"
      rc=$?
      set -e
    fi
  fi

  if [[ ! -s "${out_file}.tmp" ]]; then
    echo "no candidates found (views may not exist or no matches)" >&2
    touch "${out_file}"
    rm -f "${out_file}.tmp"
    return 0
  fi

  # sanitize and finalize
  grep -vE '^\s*$' "${out_file}.tmp" | sed -e 's/\r$//' > "${out_file}"
  rm -f "${out_file}.tmp"
}

echo "Selecting candidates (limit=${LIMIT})..."
select_candidates "${SELECTED_IDS}"
SEL_COUNT="$(wc -l < "${SELECTED_IDS}" | tr -d ' ')"
echo "${SEL_COUNT}" > "${RUN_DIR}/selected_count.txt"

if [[ "${SEL_COUNT}" == "0" ]]; then
  echo "No candidates selected; exiting"
  echo "" > "${RETRY_LIST}"
  echo "Run dir: ${RUN_DIR}"
  exit 0
fi

echo "Selected ${SEL_COUNT} candidates"
echo "Running replay..."

export PROOF_ROOT
export SKIP_IF_PASS

# Run replay on selected ids
"${REPLAY}" "${SELECTED_IDS}" 2>&1 | tee "${RUN_DIR}/replay_stdout.txt"

# Discover summary CSV path from replay output
SUMMARY_CSV="$(grep "^CSV:" "${RUN_DIR}/replay_stdout.txt" | tail -n1 | sed 's/CSV:[[:space:]]*//' | tr -d '\r')"
if [[ -z "${SUMMARY_CSV}" || ! -f "${SUMMARY_CSV}" ]]; then
  # Fallback: look for most recent summary in PROOF_ROOT
  SUMMARY_CSV="$(find "${PROOF_ROOT}" -name 'shadow_batch_summary.csv' -type f -mmin -5 2>/dev/null | head -n1)"
fi

if [[ -n "${SUMMARY_CSV}" && -f "${SUMMARY_CSV}" ]]; then
  cp -f "${SUMMARY_CSV}" "${RUN_DIR}/shadow_batch_summary.csv"
  awk -F',' 'NR>1 && $2=="FAIL" {print $1}' "${RUN_DIR}/shadow_batch_summary.csv" > "${RETRY_LIST}"
  RETRY_COUNT="$(wc -l < "${RETRY_LIST}" | tr -d ' ')"
  echo "${RETRY_COUNT}" > "${RUN_DIR}/retry_count.txt"

  PASS_COUNT="$(awk -F',' 'NR>1 && $2=="PASS" {count++} END {print count+0}' "${RUN_DIR}/shadow_batch_summary.csv")"
  FAIL_COUNT="$(awk -F',' 'NR>1 && $2=="FAIL" {count++} END {print count+0}' "${RUN_DIR}/shadow_batch_summary.csv")"
else
  echo "warning: replay did not produce a summary CSV at expected path" 1>&2
  echo "" > "${RETRY_LIST}"
  echo "0" > "${RUN_DIR}/retry_count.txt"
  PASS_COUNT=0
  FAIL_COUNT=0
  RETRY_COUNT=0
fi

echo ""
echo "=============================================="
echo "AUTOPICK SUMMARY"
echo "=============================================="
echo "Run dir:       ${RUN_DIR}"
echo "Selected:      ${SEL_COUNT}"
echo "Passed:        ${PASS_COUNT:-0}"
echo "Failed:        ${FAIL_COUNT:-0}"
echo "Retry list:    ${RETRY_LIST}"
echo "=============================================="
