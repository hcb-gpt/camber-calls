#!/usr/bin/env bash
set -euo pipefail

# scan-transcript-regression-sample.sh
# Samples recent calls with transcripts and runs:
#   scan_transcript_for_projects(transcript_text, similarity_threshold, min_alias_length)
#
# Usage:
#   ./scripts/scan-transcript-regression-sample.sh           # default n=20
#   ./scripts/scan-transcript-regression-sample.sh 50        # sample 50
#
# Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (loaded via scripts/load-env.sh)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

N="${1:-20}"
SIM_THRESHOLD="0.4"
MIN_ALIAS_LEN="3"

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 1
  fi
done

for bin in jq rg curl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: Missing required binary: ${bin}" >&2
    exit 1
  fi
done

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
  curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/scan_transcript_for_projects" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$body" --max-time 120
}

calls="$(api_get "calls_raw" \
  --data-urlencode "select=interaction_id,ingested_at_utc" \
  --data-urlencode "transcript=not.is.null" \
  --data-urlencode "order=ingested_at_utc.desc" \
  --data-urlencode "limit=200")"

ids="$(jq -r '.[].interaction_id' <<<"$calls" | rg -v '^cll_(SMOKE_TEST|SHADOW_)' | head -n "$N")"

actual_n="$(wc -l <<<"$ids" | tr -d ' ')"
echo "scan_transcript_for_projects regression sample (n=${actual_n})"
echo "threshold=${SIM_THRESHOLD} min_alias_length=${MIN_ALIAS_LEN}"
echo ""

bad_phonetic_calls=0
total_calls=0

while read -r id; do
  [[ -z "$id" ]] && continue
  total_calls=$((total_calls + 1))

  row="$(api_get "calls_raw" \
    --data-urlencode "select=transcript" \
    --data-urlencode "interaction_id=eq.${id}" \
    --data-urlencode "limit=1")"
  transcript="$(jq -r '.[0].transcript // ""' <<<"$row")"

  scan="$(rpc_scan "$transcript")"

  total="$(jq 'length' <<<"$scan")"
  fuzzy="$(jq '[.[] | select(.match_type | startswith("fuzzy"))] | length' <<<"$scan")"
  phonetic="$(jq '[.[] | select(.match_type | test("phonetic"))] | length' <<<"$scan")"
  if [[ "$phonetic" != "0" ]]; then
    bad_phonetic_calls=$((bad_phonetic_calls + 1))
  fi

  echo "${id} total=${total} fuzzy=${fuzzy} phonetic=${phonetic}"

  jq -r '.[] | select((.match_type | startswith("fuzzy")) and (.score < 0.56)) |
    "  near_threshold term=\(.matched_term) alias=\(.matched_alias) project=\(.project_name) score=\(.score) type=\(.match_type)"' <<<"$scan"
done <<<"$ids"

echo ""
echo "done calls=${total_calls} bad_phonetic_calls=${bad_phonetic_calls}"

