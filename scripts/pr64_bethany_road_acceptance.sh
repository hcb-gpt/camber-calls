#!/usr/bin/env bash
set -euo pipefail

# pr64_bethany_road_acceptance.sh
#
# Purpose:
#   Post-merge acceptance helper for PR64 Bethany Road anchor work.
#   For each call_id, fetch transcript from calls_raw and run RPC:
#     public.scan_transcript_for_projects(transcript_text, similarity_threshold, min_alias_length)
#   Then report whether:
#     - matched_term includes "bethany road" (case-insensitive)
#     - a Winship project candidate appears in RPC results
#
# Usage:
#   ./scripts/pr64_bethany_road_acceptance.sh
#   ./scripts/pr64_bethany_road_acceptance.sh cll_... cll_...
#
# Requires:
#   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (loaded by scripts/load-env.sh)
#   jq, curl

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 1
  fi
done

for bin in jq curl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: Missing required binary: ${bin}" >&2
    exit 1
  fi
done

SIM_THRESHOLD="${SIM_THRESHOLD:-0.40}"
MIN_ALIAS_LEN="${MIN_ALIAS_LEN:-3}"

DEFAULT_CALLS=(
  "cll_06DH6R3R11ZDBE7S7VV29GS4P8"
  "cll_06DH6SXG3NV6D86D0Y7CCPAB94"
)

CALLS=()
if [[ $# -gt 0 ]]; then
  CALLS=("$@")
else
  CALLS=("${DEFAULT_CALLS[@]}")
fi

api_get() {
  local table="$1"; shift
  curl -sS -G "${SUPABASE_URL}/rest/v1/${table}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "$@" --max-time 60
}

rpc_scan() {
  local transcript="$1"
  local body
  body="$(jq -n --arg t "$transcript" --argjson s "$SIM_THRESHOLD" --argjson m "$MIN_ALIAS_LEN" \
    '{transcript_text:$t, similarity_threshold:$s, min_alias_length:$m}')"
  curl -sS -w "\n%{http_code}" -X POST "${SUPABASE_URL}/rest/v1/rpc/scan_transcript_for_projects" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body" --max-time 120
}

echo "PR64_BETHANY_ACCEPTANCE threshold=${SIM_THRESHOLD} min_alias_length=${MIN_ALIAS_LEN}"

pass=0
fail=0

for call_id in "${CALLS[@]}"; do
  row="$(api_get "calls_raw" \
    --data-urlencode "select=transcript" \
    --data-urlencode "interaction_id=eq.${call_id}" \
    --data-urlencode "order=ingested_at_utc.desc" \
    --data-urlencode "limit=1")"
  transcript="$(jq -r '.[0].transcript // ""' <<<"$row")"

  if [[ -z "${transcript}" || "${transcript}" == "null" ]]; then
    echo "CALL ${call_id} RESULT=FAIL reason=no_transcript"
    fail=$((fail + 1))
    continue
  fi

  scan_resp="$(rpc_scan "$transcript")"
  scan_http="$(printf '%s\n' "$scan_resp" | tail -n1)"
  scan_body="$(printf '%s\n' "$scan_resp" | sed '$d')"

  if [[ "$scan_http" != "200" ]]; then
    msg="$(printf '%s' "$scan_body" | tr '\n' ' ' | head -c 220)"
    echo "CALL ${call_id} RESULT=FAIL reason=rpc_http_${scan_http} body_excerpt=${msg}"
    fail=$((fail + 1))
    continue
  fi

  if jq -e 'type=="object" and has("message")' <<<"$scan_body" >/dev/null 2>&1; then
    code="$(jq -r '.code // "unknown"' <<<"$scan_body" 2>/dev/null || echo unknown)"
    msg="$(jq -r '.message // "unknown"' <<<"$scan_body" 2>/dev/null || echo unknown)"
    msg="$(printf '%s' "$msg" | tr '\n' ' ' | head -c 220)"
    echo "CALL ${call_id} RESULT=FAIL reason=rpc_error code=${code} message=${msg}"
    fail=$((fail + 1))
    continue
  fi

  if ! jq -e 'type=="array"' <<<"$scan_body" >/dev/null 2>&1; then
    echo "CALL ${call_id} RESULT=FAIL reason=rpc_unexpected_shape"
    fail=$((fail + 1))
    continue
  fi

  total="$(jq 'length' <<<"$scan_body")"
  has_bethany="$(jq '[.[] | select(((.matched_term // "" | ascii_downcase) | contains("bethany road")) or ((.matched_alias // "" | ascii_downcase) | contains("bethany road")))] | length' <<<"$scan_body")"
  has_winship="$(jq '[.[] | select(((.project_name // "" | ascii_downcase) | contains("winship")) or ((.matched_alias // "" | ascii_downcase) | contains("winship")))] | length' <<<"$scan_body")"

  verdict="FAIL"
  if [[ "$has_bethany" -gt 0 && "$has_winship" -gt 0 ]]; then
    verdict="PASS"
  fi

  echo "CALL ${call_id} RESULT=${verdict} total_matches=${total} bethany_hits=${has_bethany} winship_hits=${has_winship}"

  if [[ "${verdict}" == "PASS" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    jq -r '.[] | select((.matched_term // "" | ascii_downcase) | contains("bethany") or (.project_name // "" | ascii_downcase) | contains("winship")) |
      "  match_type=\(.match_type) score=\(.score) term=\(.matched_term) alias=\(.matched_alias) project=\(.project_name)"' <<<"$scan_body" || true
  fi
done

echo "PR64_BETHANY_SUMMARY pass=${pass} fail=${fail}"
if [[ "${fail}" -eq 0 ]]; then
  exit 0
fi
exit 1
