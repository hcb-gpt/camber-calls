#!/usr/bin/env bash
set -euo pipefail

# shadow_batch_replay.sh
# STRAT TURN 72: GPT-DEV-3 shadow batch skeleton
#
# Batch replay: for each interaction_id:
#   1) (optional) skip if already PASS via score_interaction()
#   2) POST /functions/v1/segment-call
#   3) query score_interaction() and emit one CSV row
#
# Requirements:
#   - curl, jq
#   - psql OR score_interaction RPC available
#
# Env vars (required):
#   SUPABASE_URL                  e.g. https://<ref>.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY     service role key
#   EDGE_SHARED_SECRET            edge function auth
#
# Env vars (optional):
#   DATABASE_URL                  postgres connection (for psql fallback)
#   MAX_ATTEMPTS                  default 3
#   SKIP_IF_PASS                  default 1 (1=true, 0=false)
#   PROOF_ROOT                    default /tmp/proofs/shadow_batch
#
# Usage:
#   ./scripts/shadow_batch_replay.sh interaction_ids.txt
#   - interaction_ids.txt: one interaction_id per line (blank lines and # comments ignored)

usage() {
  echo "usage: $0 <interaction_ids.txt>" 1>&2
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

IDS_FILE="$1"
if [[ ! -f "$IDS_FILE" ]]; then
  echo "error: file not found: $IDS_FILE" 1>&2
  exit 2
fi

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"
: "${EDGE_SHARED_SECRET:?EDGE_SHARED_SECRET is required}"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
SKIP_IF_PASS="${SKIP_IF_PASS:-1}"
PROOF_ROOT="${PROOF_ROOT:-/tmp/proofs/shadow_batch}"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="${PROOF_ROOT}/${RUN_ID}"
mkdir -p "${RUN_DIR}"

CSV_OUT="${RUN_DIR}/shadow_batch_summary.csv"
echo "interaction_id,status,gen_max,spans_active,attributions,review_items,review_gap,override_reseeds,http_status,attempts,latency_ms" > "${CSV_OUT}"

# ---- helpers ----

now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; print(int(time.time()*1000))"
  else
    echo $(($(date +%s) * 1000))
  fi
}

sleep_ms() {
  local ms="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import time; time.sleep($ms/1000.0)"
  else
    sleep $(echo "scale=3; $ms/1000" | bc)
  fi
}

# Call score_interaction RPC via REST
score_interaction() {
  local interaction_id="$1"
  curl -s --max-time 30 -X POST "${SUPABASE_URL}/rest/v1/rpc/score_interaction" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -d "{\"p_interaction_id\":\"${interaction_id}\"}" 2>/dev/null || echo '[]'
}

# Parse scoreboard JSON to CSV-like values
parse_scoreboard() {
  local json="$1"
  # Returns: interaction_id,gen_max,spans_active,attributions,review_items,review_gap,override_reseeds,status
  echo "$json" | jq -r '.[0] | [
    .interaction_id // "",
    .gen_max // 0,
    .spans_active // 0,
    .attributions // 0,
    .review_items // 0,
    .review_gap // 0,
    .override_reseeds // 0,
    (if (.spans_active // 0) > 0 and (.review_gap // 0) == 0 then "PASS" else "FAIL" end)
  ] | @csv' 2>/dev/null | tr -d '"' || echo ",,,,,,,"
}

call_admin_reseed() {
  local interaction_id="$1"
  local idem_key="$2"
  local out_dir="$3"

  local url="${SUPABASE_URL}/functions/v1/admin-reseed"
  local body="{\"interaction_id\":\"${interaction_id}\",\"mode\":\"reseed_and_close_loop\",\"idempotency_key\":\"${idem_key}\",\"reason\":\"shadow_batch_replay\"}"

  local attempt=0
  local http_status="000"
  local latency_ms="0"
  local delay=500

  while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
    attempt=$((attempt+1))
    local t0
    t0="$(now_ms)"

    http_status="$(curl -s --max-time 180 -o "${out_dir}/reseed_response.json" -w "%{http_code}" \
      -X POST "$url" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
      -H "X-Source: admin-reseed" \
      -H "Content-Type: application/json" \
      --data "$body" || echo "000")"

    local t1
    t1="$(now_ms)"
    latency_ms="$((t1 - t0))"

    echo "${http_status}" > "${out_dir}/http_status.txt"
    echo "${latency_ms}" > "${out_dir}/latency_ms.txt"
    echo "${attempt}" > "${out_dir}/attempts.txt"

    if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
      echo "${http_status},${attempt},${latency_ms}"
      return 0
    fi

    # Retryable: 5xx or network (000)
    if [[ "$http_status" == "000" || "$http_status" =~ ^5[0-9][0-9]$ ]]; then
      if [[ $attempt -ge $MAX_ATTEMPTS ]]; then
        echo "${http_status},${attempt},${latency_ms}"
        return 1
      fi
      sleep_ms "$delay"
      delay=$((delay * 2))
      continue
    fi

    # Non-retryable (4xx)
    echo "${http_status},${attempt},${latency_ms}"
    return 1
  done

  echo "${http_status},${attempt},${latency_ms}"
  return 1
}

sanitize_ids() {
  grep -vE '^\s*(#|$)' "$IDS_FILE" | sed -e 's/\r$//' | while read -r line; do echo "$line"; done
}

# ---- main loop ----

total=0
passed=0
failed=0

while IFS= read -r interaction_id; do
  interaction_id="$(echo "$interaction_id" | xargs)"
  [[ -z "$interaction_id" ]] && continue

  total=$((total+1))
  OUT_DIR="${RUN_DIR}/${interaction_id}"
  mkdir -p "${OUT_DIR}"

  # 1) Skip if already PASS (optional)
  if [[ "$SKIP_IF_PASS" == "1" ]]; then
    scoreboard_json="$(score_interaction "$interaction_id")"
    row="$(parse_scoreboard "$scoreboard_json")"
    status="$(echo "$row" | cut -d',' -f8)"

    if [[ "$status" == "PASS" ]]; then
      echo "SKIP (already PASS): $interaction_id"
      echo "$scoreboard_json" > "${OUT_DIR}/scoreboard.json"
      IFS=',' read -r iid gen_max spans_active attributions review_items review_gap override_reseeds stat <<< "$row"
      echo "${iid},${stat},${gen_max},${spans_active},${attributions},${review_items},${review_gap},${override_reseeds},skipped,0,0" >> "${CSV_OUT}"
      passed=$((passed+1))
      continue
    fi
  fi

  # 2) Call admin-reseed
  IDEM_KEY="shadow_batch-${RUN_ID}-${interaction_id}"
  echo "${IDEM_KEY}" > "${OUT_DIR}/idempotency_key.txt"

  set +e
  call_meta="$(call_admin_reseed "$interaction_id" "$IDEM_KEY" "$OUT_DIR")"
  call_rc=$?
  set -e
  IFS=',' read -r http_status attempts latency_ms <<< "$call_meta"

  # 3) Scoreboard proof
  scoreboard_json="$(score_interaction "$interaction_id")"
  echo "$scoreboard_json" > "${OUT_DIR}/scoreboard.json"
  row="$(parse_scoreboard "$scoreboard_json")"

  if [[ -z "$row" || "$row" == ",,,,,,," ]]; then
    echo "FAIL (scoreboard error): $interaction_id"
    echo "${interaction_id},FAIL,,,,,,,${http_status},${attempts},${latency_ms}" >> "${CSV_OUT}"
    failed=$((failed+1))
    continue
  fi

  IFS=',' read -r iid gen_max spans_active attributions review_items review_gap override_reseeds status <<< "$row"

  # 4) Final status
  final_status="$status"
  if [[ $call_rc -ne 0 ]]; then
    final_status="FAIL"
  fi

  if [[ "$final_status" == "PASS" ]]; then
    passed=$((passed+1))
    echo "PASS: $interaction_id"
  else
    failed=$((failed+1))
    echo "FAIL: $interaction_id"
  fi

  echo "${iid},${final_status},${gen_max},${spans_active},${attributions},${review_items},${review_gap},${override_reseeds},${http_status},${attempts},${latency_ms}" >> "${CSV_OUT}"

done < <(sanitize_ids)

# ---- summary ----
echo ""
echo "=============================================="
echo "SHADOW BATCH SUMMARY"
echo "=============================================="
echo "Run ID:    ${RUN_ID}"
echo "Total:     ${total}"
echo "Passed:    ${passed}"
echo "Failed:    ${failed}"
echo "Pass Rate: $(echo "scale=1; $passed * 100 / $total" | bc 2>/dev/null || echo "N/A")%"
echo "=============================================="
echo "CSV:       ${CSV_OUT}"
echo "Artifacts: ${RUN_DIR}/"
echo "=============================================="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
exit 0
