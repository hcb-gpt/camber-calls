#!/usr/bin/env bash
# smoke_cascade.sh - Quick cascade smoke test for segment-llm + ai-router
#
# Runs:
#   1) segment-llm with synthetic multi-project transcript
#   2) ai-router in dry_run mode with synthetic context_package
#
# Usage:
#   ./scripts/smoke_cascade.sh
#
# Optional env:
#   SUPABASE_FUNCTIONS_BASE_URL  Override default "${SUPABASE_URL}/functions/v1"
#   CASCADE_TRANSCRIPT_FILE      Path to a transcript file to use instead of built-in sample
#
# Required env:
#   SUPABASE_URL
#   SUPABASE_SERVICE_ROLE_KEY
#   EDGE_SHARED_SECRET
#
# Notes:
#   - No DB writes from ai-router (dry_run=true)
#   - Synthetic IDs and projects only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/load-env.sh" >/dev/null 2>&1 || true
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    echo "Run: source ${ROOT_DIR}/scripts/load-env.sh" >&2
    exit 2
  fi
done

for cmd in curl jq mktemp; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: ${cmd}" >&2
    exit 2
  fi
done

BASE_URL="${SUPABASE_FUNCTIONS_BASE_URL:-${SUPABASE_URL}/functions/v1}"
RUN_ID="smoke-cascade-$(date +%s)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SEGMENT_PAYLOAD="${TMP_DIR}/segment_payload.json"
SEGMENT_OUT="${TMP_DIR}/segment_out.json"
ROUTER_PAYLOAD="${TMP_DIR}/router_payload.json"
ROUTER_OUT="${TMP_DIR}/router_out.json"

if [[ -n "${CASCADE_TRANSCRIPT_FILE:-}" && -f "${CASCADE_TRANSCRIPT_FILE}" ]]; then
  TRANSCRIPT="$(cat "${CASCADE_TRANSCRIPT_FILE}")"
else
  TRANSCRIPT=$'Hey team, I\'m at Madison Heights checking the electrical walkthrough and the tile order.\n\nWe still need client sign-off for the Madison Heights cabinet mockups before Friday.\n\nSwitching topics: for Wellington Ridge we need to move framing inspection to Tuesday and confirm delivery for windows on lot 12.\n\nI\'ll send a separate update for Wellington Ridge permits after I call the county office.'
fi

jq -n \
  --arg interaction_id "${RUN_ID}" \
  --arg transcript "${TRANSCRIPT}" \
  '{
    interaction_id: $interaction_id,
    transcript: $transcript,
    source: "segment-call",
    max_segments: 6,
    min_segment_chars: 120
  }' > "${SEGMENT_PAYLOAD}"

echo "== segment-llm smoke =="
SEGMENT_HTTP=$(
  curl -sS -o "${SEGMENT_OUT}" -w "%{http_code}" \
    -X POST "${BASE_URL}/segment-llm" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    -H "X-Source: smoke-test" \
    --data @"${SEGMENT_PAYLOAD}"
)

if [[ "${SEGMENT_HTTP}" != "200" ]]; then
  echo "FAIL: segment-llm HTTP ${SEGMENT_HTTP}" >&2
  cat "${SEGMENT_OUT}" >&2
  exit 1
fi

SEGMENT_OK="$(jq -r '.ok // false' "${SEGMENT_OUT}")"
if [[ "${SEGMENT_OK}" != "true" ]]; then
  echo "FAIL: segment-llm returned ok=false" >&2
  cat "${SEGMENT_OUT}" >&2
  exit 1
fi

SEGMENT_COUNT="$(jq -r '.segments | length' "${SEGMENT_OUT}")"
SEGMENT_VERSION="$(jq -r '.segmenter_version // "unknown"' "${SEGMENT_OUT}")"
SEGMENT_WARNINGS="$(jq -c '.warnings // []' "${SEGMENT_OUT}")"
echo "segmenter_version=${SEGMENT_VERSION}"
echo "segments=${SEGMENT_COUNT}"
echo "warnings=${SEGMENT_WARNINGS}"

jq -n \
  --arg span_id "${RUN_ID}-span-0" \
  --arg interaction_id "${RUN_ID}" \
  --arg transcript "${TRANSCRIPT}" \
  --arg p1 "11111111-1111-4111-8111-111111111111" \
  --arg p2 "22222222-2222-4222-8222-222222222222" \
  '{
    dry_run: true,
    context_package: {
      meta: {
        span_id: $span_id,
        interaction_id: $interaction_id
      },
      span: {
        transcript_text: $transcript
      },
      contact: {
        contact_id: null,
        contact_name: "Cascade Smoke Caller",
        floater_flag: false,
        recent_projects: [
          { project_id: $p1, project_name: "Madison Heights" }
        ]
      },
      candidates: [
        {
          project_id: $p1,
          project_name: "Madison Heights",
          address: "101 Madison Heights Dr",
          client_name: "Acme Client",
          aliases: ["madison heights", "madison"],
          status: "active",
          phase: "build",
          evidence: {
            sources: ["smoke"],
            affinity_weight: 0.7,
            assigned: true,
            alias_matches: [
              { term: "madison heights", match_type: "alias", snippet: "Madison Heights" }
            ]
          }
        },
        {
          project_id: $p2,
          project_name: "Wellington Ridge",
          address: "12 Wellington Ridge Ln",
          client_name: "Acme Client 2",
          aliases: ["wellington ridge", "wellington"],
          status: "active",
          phase: "build",
          evidence: {
            sources: ["smoke"],
            affinity_weight: 0.6,
            assigned: false,
            alias_matches: [
              { term: "wellington ridge", match_type: "alias", snippet: "Wellington Ridge" }
            ]
          }
        }
      ]
    }
  }' > "${ROUTER_PAYLOAD}"

echo "== ai-router smoke (dry_run) =="
ROUTER_HTTP=$(
  curl -sS -o "${ROUTER_OUT}" -w "%{http_code}" \
    -X POST "${BASE_URL}/ai-router" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    -H "X-Source: smoke-test" \
    --data @"${ROUTER_PAYLOAD}"
)

if [[ "${ROUTER_HTTP}" != "200" ]]; then
  echo "FAIL: ai-router HTTP ${ROUTER_HTTP}" >&2
  cat "${ROUTER_OUT}" >&2
  exit 1
fi

ROUTER_OK="$(jq -r '.ok // false' "${ROUTER_OUT}")"
if [[ "${ROUTER_OK}" != "true" ]]; then
  echo "FAIL: ai-router returned ok=false" >&2
  cat "${ROUTER_OUT}" >&2
  exit 1
fi

ROUTER_DECISION="$(jq -r '.decision // "unknown"' "${ROUTER_OUT}")"
ROUTER_CONFIDENCE="$(jq -r '.confidence // 0' "${ROUTER_OUT}")"
CASCADE_PROVIDER="$(jq -r '.cascade.winner_provider // "none"' "${ROUTER_OUT}")"
CASCADE_MODEL="$(jq -r '.cascade.winner_model // "none"' "${ROUTER_OUT}")"
CASCADE_STAGE="$(jq -r '.cascade.winner_stage // "none"' "${ROUTER_OUT}")"
CASCADE_CONSENSUS="$(jq -r '.cascade.consensus_assign // false' "${ROUTER_OUT}")"
CASCADE_WARNINGS="$(jq -c '.cascade.warnings // []' "${ROUTER_OUT}")"

echo "decision=${ROUTER_DECISION} confidence=${ROUTER_CONFIDENCE}"
echo "cascade_provider=${CASCADE_PROVIDER}"
echo "cascade_model=${CASCADE_MODEL}"
echo "cascade_stage=${CASCADE_STAGE}"
echo "cascade_consensus_assign=${CASCADE_CONSENSUS}"
echo "cascade_warnings=${CASCADE_WARNINGS}"

echo ""
echo "PASS: cascade smoke completed (${RUN_ID})"
