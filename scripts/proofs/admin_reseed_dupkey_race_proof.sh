#!/usr/bin/env bash
set -euo pipefail

# Proves admin-reseed duplicate-key race hardening.
# 1) Double-hit same interaction sequentially
# 2) Hit same interaction concurrently
# 3) Run a small concurrent batch (one call per interaction id)
#
# Usage:
#   ./scripts/proofs/admin_reseed_dupkey_race_proof.sh <interaction_id> [batch_ids_csv]
#
# Example:
#   ./scripts/proofs/admin_reseed_dupkey_race_proof.sh \
#     cll_06E4K02P55WQZ1JN7SAVZ3D318 \
#     cll_06E4K02P55WQZ1JN7SAVZ3D318,cll_06E4600Y4SSKD9MFM63EPB9MCW,cll_DEV4OWNERWARN_20260215T192538Z

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${REPO_ROOT}/scripts/load-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/load-env.sh"
elif [[ -f "${HOME}/.camber/load-credentials.sh" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.camber/load-credentials.sh"
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: missing env var ${var}" >&2
    exit 2
  fi
done

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <interaction_id> [batch_ids_csv]" >&2
  exit 2
fi

PRIMARY_ID="$1"
BATCH_IDS_CSV="${2:-${PRIMARY_ID}}"
MODE="resegment_only"
CONCURRENT_SAME_N=8

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${REPO_ROOT}/artifacts/admin_reseed_dupkey_race/${RUN_TS}_${PRIMARY_ID}"
mkdir -p "${OUT_DIR}"

URL="${SUPABASE_URL}/functions/v1/admin-reseed"

call_reseed() {
  local interaction_id="$1"
  local label="$2"
  local idem="dupkey-proof-${label}-${RUN_TS}-$$"
  local out_file="${OUT_DIR}/${label}.txt"
  curl -sS -m 220 -w "\nHTTP_STATUS:%{http_code}\nTOTAL:%{time_total}\n" \
    -X POST "${URL}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    -H "X-Source: admin-reseed" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -d "{\"interaction_id\":\"${interaction_id}\",\"mode\":\"${MODE}\",\"idempotency_key\":\"${idem}\",\"reason\":\"dupkey_race_proof\"}" \
    > "${out_file}"
}

summarize_file() {
  local f="$1"
  local code total err detail
  code="$(grep 'HTTP_STATUS:' "${f}" | tail -n1 | cut -d: -f2)"
  total="$(grep 'TOTAL:' "${f}" | tail -n1 | cut -d: -f2)"
  err="$(awk 'BEGIN{json=1} /^HTTP_STATUS:/{json=0} {if(json) print}' "${f}" | jq -r '.error // .receipt.status // "none"' 2>/dev/null || echo "parse_error")"
  detail="$(awk 'BEGIN{json=1} /^HTTP_STATUS:/{json=0} {if(json) print}' "${f}" | jq -r '.detail // empty' 2>/dev/null || true)"
  echo "$(basename "${f}") http=${code} total=${total} err=${err} detail=${detail}"
}

echo "PRIMARY_ID=${PRIMARY_ID}" | tee "${OUT_DIR}/summary.log"
echo "BATCH_IDS=${BATCH_IDS_CSV}" | tee -a "${OUT_DIR}/summary.log"
echo "MODE=${MODE}" | tee -a "${OUT_DIR}/summary.log"

echo "=== step1: sequential double-hit ===" | tee -a "${OUT_DIR}/summary.log"
call_reseed "${PRIMARY_ID}" "seq_1"
call_reseed "${PRIMARY_ID}" "seq_2"

echo "=== step2: concurrent same interaction (${CONCURRENT_SAME_N}) ===" | tee -a "${OUT_DIR}/summary.log"
for i in $(seq 1 "${CONCURRENT_SAME_N}"); do
  call_reseed "${PRIMARY_ID}" "same_concurrent_${i}" &
done
wait

echo "=== step3: concurrent small batch ===" | tee -a "${OUT_DIR}/summary.log"
IFS=',' read -r -a batch_ids <<< "${BATCH_IDS_CSV}"
for i in "${!batch_ids[@]}"; do
  echo "${batch_ids[$i]}" > "${OUT_DIR}/batch_id_$((i+1)).txt"
done
for i in "${!batch_ids[@]}"; do
  idx=$((i + 1))
  call_reseed "${batch_ids[$i]}" "batch_${idx}" &
done
wait

echo "=== results ===" | tee -a "${OUT_DIR}/summary.log"
FAILURES=0
for f in "${OUT_DIR}"/*.txt; do
  [[ "$(basename "$f")" == batch_id_* ]] && continue
  line="$(summarize_file "${f}")"
  echo "${line}" | tee -a "${OUT_DIR}/summary.log"
  code="$(echo "${line}" | sed -E 's/.*http=([0-9]+).*/\1/')"
  if [[ "${code}" != "200" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
done

echo "FAILURES=${FAILURES}" | tee -a "${OUT_DIR}/summary.log"
echo "OUT_DIR=${OUT_DIR}" | tee -a "${OUT_DIR}/summary.log"

if [[ "${FAILURES}" -eq 0 ]]; then
  echo "RACE_PROOF_PASS"
  exit 0
fi

echo "RACE_PROOF_FAIL"
exit 1
