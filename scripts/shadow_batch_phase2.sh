#!/usr/bin/env bash
set -euo pipefail

# shadow_batch_phase2.sh
# Phase 2 wrapper:
#   1) Select candidate interaction_ids from DB (gaps and/or spans_total=0)
#   2) Run shadow_batch_replay.sh on the candidate list
#   3) Emit:
#        - selected_ids.txt
#        - shadow_batch_summary.csv (from replay)
#        - retry_list_failures.txt (interaction_ids where status == FAIL)
#
# Requirements:
#   - bash, psql, python3
#   - shadow_batch_replay.sh on PATH or in same directory
#
# Env vars (required; forwarded to replay script):
#   SUPABASE_URL
#   SUPABASE_SERVICE_ROLE_KEY
#   EDGE_SHARED_SECRET
#   SUPABASE_DB_URL
#
# Env vars (optional):
#   LIMIT                default 250
#   PROOF_ROOT           default /tmp/proofs/shadow_batch
#   SKIP_IF_PASS         default 1 (forwarded to replay script)
#   REPLAY_SCRIPT        override path to replay script
#
# Usage:
#   ./shadow_batch_phase2.sh
#   LIMIT=1000 ./shadow_batch_phase2.sh

: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"
: "${EDGE_SHARED_SECRET:?EDGE_SHARED_SECRET is required}"

LIMIT="${LIMIT:-250}"
PROOF_ROOT="${PROOF_ROOT:-/tmp/proofs/shadow_batch}"
SKIP_IF_PASS="${SKIP_IF_PASS:-1}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLAY="${REPLAY_SCRIPT:-${HERE}/shadow_batch_replay.sh}"

if [[ ! -x "${REPLAY}" ]]; then
  echo "error: replay script not found or not executable: ${REPLAY}" 1>&2
  exit 2
fi

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${PROOF_ROOT}/${RUN_ID}"
mkdir -p "${RUN_DIR}"

SELECTED_IDS="${RUN_DIR}/selected_ids.txt"
RETRY_LIST="${RUN_DIR}/retry_list_failures.txt"

select_candidates() {
  local out_file="$1"

  # Query A: interactions with review gaps
  local q_a
  q_a=$(cat <<SQL
SELECT DISTINCT interaction_id
FROM v_review_coverage_gaps
WHERE review_gap > 0
ORDER BY interaction_id
LIMIT ${LIMIT};
SQL
)

  # Query B: calls_raw with no spans
  local q_b
  q_b=$(cat <<SQL
SELECT DISTINCT id AS interaction_id
FROM calls_raw
WHERE COALESCE(spans_total, 0) = 0
ORDER BY id
LIMIT ${LIMIT};
SQL
)

  # Query C: union of A and B
  local q_c
  q_c=$(cat <<SQL
WITH a AS (
  SELECT interaction_id
  FROM v_review_coverage_gaps
  WHERE review_gap > 0
),
b AS (
  SELECT id AS interaction_id
  FROM calls_raw
  WHERE COALESCE(spans_total, 0) = 0
)
SELECT DISTINCT interaction_id
FROM (
  SELECT interaction_id FROM a
  UNION
  SELECT interaction_id FROM b
) u
ORDER BY interaction_id
LIMIT ${LIMIT};
SQL
)

  # Attempt union first
  set +e
  psql "${SUPABASE_DB_URL}" -X -q -A -t -v ON_ERROR_STOP=1 -c "$q_c" > "${out_file}.tmp" 2>/dev/null
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    # union failed; try gaps only
    set +e
    psql "${SUPABASE_DB_URL}" -X -q -A -t -v ON_ERROR_STOP=1 -c "$q_a" > "${out_file}.tmp" 2>/dev/null
    rc=$?
    set -e
  fi

  if [[ $rc -ne 0 ]]; then
    # gaps failed; try calls_raw only
    set +e
    psql "${SUPABASE_DB_URL}" -X -q -A -t -v ON_ERROR_STOP=1 -c "$q_b" > "${out_file}.tmp" 2>/dev/null
    rc=$?
    set -e
  fi

  if [[ $rc -ne 0 ]]; then
    echo "error: could not select candidates; missing views/tables or insufficient privileges" 1>&2
    return 1
  fi

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

# Run replay on the selected ids
export PROOF_ROOT
export SKIP_IF_PASS
export EDGE_SHARED_SECRET
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
  echo "$(wc -l < "${RETRY_LIST}" | tr -d ' ')" > "${RUN_DIR}/retry_count.txt"
else
  echo "warning: replay did not produce a summary CSV at expected path" 1>&2
  echo "" > "${RETRY_LIST}"
  echo "0" > "${RUN_DIR}/retry_count.txt"
fi

echo ""
echo "=============================================="
echo "PHASE 2 COMPLETE"
echo "=============================================="
echo "Run dir:       ${RUN_DIR}"
echo "Selected:      ${SEL_COUNT}"
echo "Retry list:    ${RETRY_LIST}"
echo "=============================================="
