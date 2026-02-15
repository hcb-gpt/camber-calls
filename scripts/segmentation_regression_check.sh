#!/usr/bin/env bash
set -euo pipefail

# segmentation_regression_check.sh
# Repeatable proof harness for segment-llm oversize/multi-topic regressions.
#
# Default behavior:
#  1) Read current active spans from DB (before state).
#  2) Invoke segment-llm for the same transcript (candidate after state).
#  3) Evaluate acceptance checks:
#     - spans_total >= 4
#     - max segment chars <= 3000
#     - boundary_quote evidence includes "woodberry" and "sparta"
#
# Usage:
#   ./scripts/segmentation_regression_check.sh
#   ./scripts/segmentation_regression_check.sh --call-id cll_...
#   SEGMENT_LLM_URL=http://127.0.0.1:8000 ./scripts/segmentation_regression_check.sh
#   ./scripts/segmentation_regression_check.sh --skip-current
#   ./scripts/segmentation_regression_check.sh --skip-invoke
#   ./scripts/segmentation_regression_check.sh --json

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh"

CALL_ID="cll_06DG7JVSFHZ71C2GQF3XP1D804"
MIN_EXPECTED_SPANS=4
MAX_ALLOWED_SEGMENT_CHARS=3000
SEGMENT_LLM_URL="${SEGMENT_LLM_URL:-${SUPABASE_URL}/functions/v1/segment-llm}"

SKIP_CURRENT=false
SKIP_INVOKE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --call-id)
      CALL_ID="${2:-}"
      if [[ -z "$CALL_ID" ]]; then
        echo "ERROR: --call-id requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --skip-current)
      SKIP_CURRENT=true
      shift
      ;;
    --skip-invoke)
      SKIP_INVOKE=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--call-id <id>] [--skip-current] [--skip-invoke] [--json]"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 1
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

api_get() {
  local table="$1"
  shift
  curl -sS -G "${SUPABASE_URL}/rest/v1/${table}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "$@" --max-time 45
}

collect_metrics() {
  local spans_json="$1"
  jq -c '
    def quote: ((.segment_metadata.boundary_quote // .boundary_quote // "") | ascii_downcase);
    {
      spans_total: length,
      max_segment_chars: ([.[] | ((.char_end // 0) - (.char_start // 0))] | max // 0),
      has_woodberry: ([.[] | quote | contains("woodberry")] | any),
      has_sparta: ([.[] | quote | contains("sparta")] | any)
    }
  ' <<<"$spans_json"
}

evaluate_pass() {
  local metrics_json="$1"
  jq -r \
    --argjson metrics "$metrics_json" \
    --argjson min_spans "$MIN_EXPECTED_SPANS" \
    --argjson max_chars "$MAX_ALLOWED_SEGMENT_CHARS" \
    '
      ($metrics.spans_total >= $min_spans)
      and ($metrics.max_segment_chars <= $max_chars)
      and $metrics.has_woodberry
      and $metrics.has_sparta
    ' <<<"{}"
}

print_spans() {
  local label="$1"
  local spans_json="$2"
  echo "--- ${label} spans ---"
  jq -r '
    if length == 0 then
      "  (none)"
    else
      .[] | "  span_\(.span_index // "n/a"): chars=\(.char_start)-\(.char_end) len=\((.char_end - .char_start)) reason=\(.segment_reason // .boundary_reason // "n/a") quote=\((.segment_metadata.boundary_quote // .boundary_quote // "null"))"
    end
  ' <<<"$spans_json"
  echo ""
}

CURRENT_SPANS='[]'
CURRENT_METRICS='{}'
CURRENT_PASS="skipped"
INVOKE_SPANS='[]'
INVOKE_METRICS='{}'
INVOKE_PASS="skipped"
INVOKE_HTTP="skipped"
INVOKE_WARNINGS='[]'

if [[ "$SKIP_CURRENT" == "false" ]]; then
  CURRENT_SPANS="$(api_get "conversation_spans" \
    --data-urlencode "select=span_index,char_start,char_end,segment_reason,segment_metadata" \
    --data-urlencode "interaction_id=eq.${CALL_ID}" \
    --data-urlencode "is_superseded=eq.false" \
    --data-urlencode "order=span_index")"
  CURRENT_METRICS="$(collect_metrics "$CURRENT_SPANS")"
  CURRENT_PASS="$(evaluate_pass "$CURRENT_METRICS")"
fi

if [[ "$SKIP_INVOKE" == "false" ]]; then
  RAW_CALL="$(api_get "calls_raw" \
    --data-urlencode "select=transcript" \
    --data-urlencode "interaction_id=eq.${CALL_ID}" \
    --data-urlencode "limit=1")"
  TRANSCRIPT="$(jq -r '.[0].transcript // empty' <<<"$RAW_CALL")"
  if [[ -z "$TRANSCRIPT" ]]; then
    echo "ERROR: transcript not found for ${CALL_ID}" >&2
    exit 1
  fi

  PAYLOAD="$(jq -n \
    --arg interaction_id "$CALL_ID" \
    --arg transcript "$TRANSCRIPT" \
    '{
      interaction_id: $interaction_id,
      transcript: $transcript,
      source: "segmentation_regression_check",
      max_segments: 10,
      min_segment_chars: 200,
      max_segment_chars: 3000
    }')"

  INVOKE_RESP="$(curl -sS -w "\n%{http_code}" -X POST "${SEGMENT_LLM_URL}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    -d "$PAYLOAD" --max-time 120)"
  INVOKE_HTTP="$(echo "$INVOKE_RESP" | tail -n1)"
  INVOKE_BODY="$(echo "$INVOKE_RESP" | sed '$d')"

  if [[ ! "$INVOKE_HTTP" =~ ^2 ]]; then
    echo "ERROR: segment-llm invoke failed (HTTP ${INVOKE_HTTP})" >&2
    echo "$INVOKE_BODY" >&2
    exit 1
  fi

  INVOKE_SPANS="$(jq -c '.segments // []' <<<"$INVOKE_BODY")"
  INVOKE_WARNINGS="$(jq -c '.warnings // []' <<<"$INVOKE_BODY")"
  INVOKE_METRICS="$(collect_metrics "$INVOKE_SPANS")"
  INVOKE_PASS="$(evaluate_pass "$INVOKE_METRICS")"
fi

if [[ "$JSON_OUTPUT" == "false" ]]; then
  echo "segmentation_regression_check"
  echo "call_id=${CALL_ID}"
  echo "segment_llm_url=${SEGMENT_LLM_URL}"
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  if [[ "$SKIP_CURRENT" == "false" ]]; then
    print_spans "current" "$CURRENT_SPANS"
    echo "current_metrics=$(jq -c . <<<"$CURRENT_METRICS")"
    echo "current_pass=${CURRENT_PASS}"
    echo ""
  fi

  if [[ "$SKIP_INVOKE" == "false" ]]; then
    print_spans "invoked" "$INVOKE_SPANS"
    echo "invoke_http=${INVOKE_HTTP}"
    echo "invoke_warnings=${INVOKE_WARNINGS}"
    echo "invoke_metrics=$(jq -c . <<<"$INVOKE_METRICS")"
    echo "invoke_pass=${INVOKE_PASS}"
    echo ""
  fi
fi

RESULT_JSON="$(jq -n \
  --arg call_id "$CALL_ID" \
  --arg segment_llm_url "$SEGMENT_LLM_URL" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson current_metrics "$CURRENT_METRICS" \
  --arg current_pass "$CURRENT_PASS" \
  --argjson invoke_metrics "$INVOKE_METRICS" \
  --arg invoke_pass "$INVOKE_PASS" \
  --arg invoke_http "$INVOKE_HTTP" \
  --argjson invoke_warnings "$INVOKE_WARNINGS" \
  '{
    call_id: $call_id,
    segment_llm_url: $segment_llm_url,
    timestamp: $timestamp,
    acceptance: {
      min_expected_spans: '"${MIN_EXPECTED_SPANS}"',
      max_allowed_segment_chars: '"${MAX_ALLOWED_SEGMENT_CHARS}"',
      required_anchor_terms: ["woodberry", "sparta"]
    },
    current: {
      metrics: $current_metrics,
      pass: $current_pass
    },
    invoked: {
      http: $invoke_http,
      warnings: $invoke_warnings,
      metrics: $invoke_metrics,
      pass: $invoke_pass
    }
  }')"

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$RESULT_JSON"
else
  echo "SEGMENTATION_REGRESSION $(jq -r '. | @json' <<<"$RESULT_JSON")"
fi

# Exit non-zero if invoked run was requested and did not satisfy acceptance.
if [[ "$SKIP_INVOKE" == "false" && "$INVOKE_PASS" != "true" ]]; then
  exit 1
fi
