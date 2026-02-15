#!/usr/bin/env bash
set -euo pipefail

# span_char_offsets_nonnull_check.sh
# Regression proof for conversation_spans char offset integrity.
#
# Default IDs are STRAT-reported failures. You can override by passing IDs:
#   ./scripts/span_char_offsets_nonnull_check.sh cll_x cll_y
#   ./scripts/span_char_offsets_nonnull_check.sh --json

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh"

DEFAULT_IDS=(
  "cll_06E471A9CNR6X6X14E6P6BY15W"
  "cll_06E118603XV5F7AXAJMQVR2C8R"
  "cll_06E4600Y4SSKD9MFM63EPB9MCW"
)

JSON_OUTPUT=false
IDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--json] [interaction_id ...]"
      exit 0
      ;;
    *)
      IDS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#IDS[@]} -eq 0 ]]; then
  IDS=("${DEFAULT_IDS[@]}")
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 2
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

api_get() {
  local table="$1"
  shift
  curl -sS -G "${SUPABASE_URL}/rest/v1/${table}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "$@" --max-time 30
}

RESULTS='[]'
TOTAL_NULL_ROWS=0
TOTAL_ROWS=0

for iid in "${IDS[@]}"; do
  SPANS="$(api_get "conversation_spans" \
    --data-urlencode "select=interaction_id,span_index,char_start,char_end,segment_generation,is_superseded" \
    --data-urlencode "interaction_id=eq.${iid}" \
    --data-urlencode "is_superseded=eq.false" \
    --data-urlencode "order=span_index")"

  ROW_COUNT="$(jq 'length' <<<"$SPANS")"
  NULL_COUNT="$(jq '[.[] | select(.char_start == null or .char_end == null)] | length' <<<"$SPANS")"
  MAX_GENERATION="$(jq '[.[].segment_generation // 0] | max // 0' <<<"$SPANS")"

  TOTAL_ROWS=$((TOTAL_ROWS + ROW_COUNT))
  TOTAL_NULL_ROWS=$((TOTAL_NULL_ROWS + NULL_COUNT))

  RESULTS="$(jq \
    --arg iid "$iid" \
    --argjson row_count "$ROW_COUNT" \
    --argjson null_count "$NULL_COUNT" \
    --argjson max_generation "$MAX_GENERATION" \
    --argjson spans "$SPANS" \
    '. + [{
      interaction_id: $iid,
      row_count: $row_count,
      null_offset_rows: $null_count,
      max_segment_generation: $max_generation,
      spans: $spans
    }]' <<<"$RESULTS")"
done

PASS="true"
if [[ "$TOTAL_NULL_ROWS" -gt 0 ]]; then
  PASS="false"
fi

OUTPUT="$(jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson total_rows "$TOTAL_ROWS" \
  --argjson total_null_rows "$TOTAL_NULL_ROWS" \
  --arg pass "$PASS" \
  --argjson results "$RESULTS" \
  '{
    timestamp: $timestamp,
    total_rows: $total_rows,
    total_null_rows: $total_null_rows,
    pass: $pass,
    results: $results
  }')"

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$OUTPUT"
else
  echo "span_char_offsets_nonnull_check"
  echo "timestamp=$(jq -r '.timestamp' <<<"$OUTPUT")"
  echo ""
  jq -r '.results[] |
    "interaction_id=\(.interaction_id) rows=\(.row_count) null_offset_rows=\(.null_offset_rows) max_generation=\(.max_segment_generation)"' <<<"$OUTPUT"
  echo ""
  echo "total_rows=$(jq -r '.total_rows' <<<"$OUTPUT")"
  echo "total_null_rows=$(jq -r '.total_null_rows' <<<"$OUTPUT")"
  echo "pass=$(jq -r '.pass' <<<"$OUTPUT")"
fi

# Non-zero exit when null offsets are detected.
if [[ "$PASS" != "true" ]]; then
  exit 1
fi
