#!/usr/bin/env bash
set -euo pipefail

# lou-winship-regression-check.sh
# Repeatable regression check for Lou Winship call (cll_06E4600Y4SSKD9MFM63EPB9MCW).
# Outputs machine-parseable summary line for DATA-1 regression loop.
#
# Usage:
#   ./scripts/lou-winship-regression-check.sh
#   ./scripts/lou-winship-regression-check.sh --rerun   # re-extract all spans first
#   ./scripts/lou-winship-regression-check.sh --json     # output JSON instead of table
#
# Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, EDGE_SHARED_SECRET

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh"

CALL_ID="cll_06E4600Y4SSKD9MFM63EPB9MCW"
FUNCTION_URL="${SUPABASE_URL}/functions/v1/journal-extract"

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 1
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 1
fi

DO_RERUN=false
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rerun) DO_RERUN=true; shift ;;
    --json)  JSON_OUTPUT=true; shift ;;
    --help|-h) echo "Usage: $0 [--rerun] [--json]"; exit 0 ;;
    *) echo "ERROR: Unknown arg: $1" >&2; exit 1 ;;
  esac
done

api_get() {
  local table="$1"; shift
  curl -sS -G "${SUPABASE_URL}/rest/v1/${table}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "$@" --max-time 30
}

# 1. Rerun extraction if requested
if [[ "$DO_RERUN" == "true" ]]; then
  echo "=== Re-extracting all spans for ${CALL_ID} ==="
  SPANS=$(api_get "conversation_spans" \
    --data-urlencode "select=id,span_index" \
    --data-urlencode "interaction_id=eq.${CALL_ID}" \
    --data-urlencode "is_superseded=eq.false" \
    --data-urlencode "order=span_index")

  for SPAN_ID in $(jq -r '.[].id' <<<"$SPANS"); do
    echo -n "  Extracting span ${SPAN_ID}... "
    RESP=$(curl -s -w "\n%{http_code}" -X POST "$FUNCTION_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
      -d "{\"span_id\":\"${SPAN_ID}\"}" \
      --max-time 120 2>&1 || true)
    HTTP=$(echo "$RESP" | tail -n1)
    BODY=$(echo "$RESP" | sed '$d')
    EXTRACTED=$(jq -r '.claims_extracted // 0' <<<"$BODY" 2>/dev/null || echo "?")
    WRITTEN=$(jq -r '.claims_written // 0' <<<"$BODY" 2>/dev/null || echo "?")
    echo "HTTP=${HTTP} extracted=${EXTRACTED} written=${WRITTEN}"
    sleep 2
  done
  echo ""
fi

# 2. Collect current state
echo "=== Lou Winship Regression Check: ${CALL_ID} ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Spans
SPANS=$(api_get "conversation_spans" \
  --data-urlencode "select=id,span_index,char_start,char_end,word_count,segment_reason" \
  --data-urlencode "interaction_id=eq.${CALL_ID}" \
  --data-urlencode "is_superseded=eq.false" \
  --data-urlencode "order=span_index")
SPAN_COUNT=$(jq 'length' <<<"$SPANS")
echo "--- Spans (${SPAN_COUNT}) ---"
jq -r '.[] | "  span_\(.span_index): id=\(.id) chars=\(.char_start)-\(.char_end) words=\(.word_count) reason=\(.segment_reason)"' <<<"$SPANS"
echo ""

# Attributions
SPAN_IDS=$(jq -r '[.[].id] | join(",")' <<<"$SPANS")
SPAN_IDS_FILTER=$(jq -r '[.[].id] | map("\"" + . + "\"") | join(",")' <<<"$SPANS")
ATTRIBS=$(api_get "span_attributions" \
  --data-urlencode "select=span_id,project_id,confidence,decision,attributed_at" \
  --data-urlencode "span_id=in.(${SPAN_IDS_FILTER})" \
  --data-urlencode "order=attributed_at")
echo "--- Attributions ---"
jq -r '.[] | "  \(.span_id): project=\(.project_id) conf=\(.confidence) decision=\(.decision)"' <<<"$ATTRIBS"
echo ""

# Journal claims
CLAIMS=$(api_get "journal_claims" \
  --data-urlencode "select=source_span_id,claim_type,claim_text,claim_project_id,claim_project_confidence,active" \
  --data-urlencode "call_id=eq.${CALL_ID}" \
  --data-urlencode "active=eq.true")
CLAIM_COUNT=$(jq 'length' <<<"$CLAIMS")
CLAIMS_WITH_PROJECT=$(jq '[.[] | select(.claim_project_id != null)] | length' <<<"$CLAIMS")
CLAIMS_NO_PROJECT=$(jq '[.[] | select(.claim_project_id == null)] | length' <<<"$CLAIMS")
echo "--- Journal Claims (${CLAIM_COUNT} active) ---"
echo "  with_project_id: ${CLAIMS_WITH_PROJECT}"
echo "  without_project_id: ${CLAIMS_NO_PROJECT}"
jq -r '.[] | "  [\(.claim_type)] \(.claim_text | .[0:80]) (project=\(.claim_project_id // "NULL"))"' <<<"$CLAIMS"
echo ""

# Belief claims
CLAIM_IDS=$(jq -r '[.[].claim_id // empty] | join(",")' <<<"$CLAIMS" 2>/dev/null || echo "")
BELIEF_COUNT=0
if [[ -n "$CLAIM_IDS" ]]; then
  # Try via journal_claim_id join
  JC_IDS=$(api_get "journal_claims" \
    --data-urlencode "select=claim_id" \
    --data-urlencode "call_id=eq.${CALL_ID}" \
    --data-urlencode "active=eq.true")
  JC_ID_FILTER=$(jq -r '[.[].claim_id] | map("\"" + . + "\"") | join(",")' <<<"$JC_IDS" 2>/dev/null || echo "")
  if [[ -n "$JC_ID_FILTER" ]]; then
    BELIEF_RESP=$(api_get "belief_claims" \
      --data-urlencode "select=id,claim_type,short_text" \
      --data-urlencode "journal_claim_id=in.(${JC_ID_FILTER})" 2>/dev/null || echo "[]")
    if jq -e 'type=="array"' <<<"$BELIEF_RESP" >/dev/null 2>&1; then
      BELIEF_COUNT=$(jq 'length' <<<"$BELIEF_RESP")
    fi
  fi
fi
echo "--- Belief Claims: ${BELIEF_COUNT} ---"
echo ""

# Review queue
RQ=$(api_get "review_queue" \
  --data-urlencode "select=span_id,status,resolution_action,reasons,module" \
  --data-urlencode "interaction_id=eq.${CALL_ID}")
RQ_COUNT=$(jq 'length' <<<"$RQ")
RQ_PENDING=$(jq '[.[] | select(.status == "pending")] | length' <<<"$RQ")
echo "--- Review Queue (${RQ_COUNT} items, ${RQ_PENDING} pending) ---"
jq -r '.[] | "  \(.status)/\(.resolution_action // "none") reasons=\(.reasons) module=\(.module)"' <<<"$RQ"
echo ""

# Journal runs
RUNS=$(api_get "journal_runs" \
  --data-urlencode "select=run_id,status,started_at,completed_at,claims_extracted,error_message" \
  --data-urlencode "call_id=eq.${CALL_ID}" \
  --data-urlencode "order=started_at.desc")
RUN_COUNT=$(jq 'length' <<<"$RUNS")
RUN_SUCCESS=$(jq '[.[] | select(.status == "success")] | length' <<<"$RUNS")
RUN_FAILED=$(jq '[.[] | select(.status == "failed")] | length' <<<"$RUNS")
echo "--- Journal Runs (${RUN_COUNT} total: ${RUN_SUCCESS} success, ${RUN_FAILED} failed) ---"
jq -r '.[] | "  \(.status) claims=\(.claims_extracted) started=\(.started_at) error=\(.error_message // "none")"' <<<"$RUNS"
echo ""

# ============================================================
# Speaker Identity Disambiguation Check (Lou vs Luis)
# ============================================================
IDENTITY_PASS=0
IDENTITY_FAIL=0

echo "--- Speaker Identity Disambiguation Check ---"

# (a) Lou Winship contact record
LOU_CONTACT=$(api_get "contacts" \
  --data-urlencode "select=name,contact_type,is_internal" \
  --data-urlencode "name=eq.Lou Winship" \
  --data-urlencode "limit=1")
LOU_CT=$(jq -r '.[0].contact_type // "MISSING"' <<<"$LOU_CONTACT")
LOU_INTERNAL=$(jq -r '.[0].is_internal // "MISSING"' <<<"$LOU_CONTACT")

if [[ "$LOU_CT" == "client" ]]; then
  echo "  PASS: Lou Winship contact_type=client"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: Lou Winship contact_type=${LOU_CT} (expected: client)"
  ((IDENTITY_FAIL++))
fi

if [[ "$LOU_INTERNAL" == "false" ]]; then
  echo "  PASS: Lou Winship is_internal=false"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: Lou Winship is_internal=${LOU_INTERNAL} (expected: false)"
  ((IDENTITY_FAIL++))
fi

# (b) Luis Juarez contact record
LUIS_CONTACT=$(api_get "contacts" \
  --data-urlencode "select=name,contact_type,is_internal" \
  --data-urlencode "name=eq.Luis Juarez" \
  --data-urlencode "limit=1")
LUIS_CT=$(jq -r '.[0].contact_type // "MISSING"' <<<"$LUIS_CONTACT")
LUIS_INTERNAL=$(jq -r '.[0].is_internal // "MISSING"' <<<"$LUIS_CONTACT")

if [[ "$LUIS_INTERNAL" == "false" ]]; then
  echo "  PASS: Luis Juarez is_internal=false"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: Luis Juarez is_internal=${LUIS_INTERNAL} (expected: false)"
  ((IDENTITY_FAIL++))
fi

if [[ "$LUIS_CT" == "vendor" || "$LUIS_CT" == "subcontractor" ]]; then
  echo "  PASS: Luis Juarez contact_type=${LUIS_CT}"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: Luis Juarez contact_type=${LUIS_CT} (expected: vendor or subcontractor)"
  ((IDENTITY_FAIL++))
fi

# (c) Alias resolution for "Lou" — should match Lou Winship, not Luis Juarez
LOU_ALIAS=$(api_get "contacts" \
  --data-urlencode "select=name" \
  --data-urlencode "aliases=cs.{Lou}" \
  --data-urlencode "limit=5")
LOU_ALIAS_NAMES=$(jq -r '[.[].name] | join(", ")' <<<"$LOU_ALIAS")
LOU_ALIAS_HAS_LOU=$(jq '[.[].name] | any(. == "Lou Winship")' <<<"$LOU_ALIAS")
LOU_ALIAS_HAS_LUIS=$(jq '[.[].name] | any(. == "Luis Juarez")' <<<"$LOU_ALIAS")

if [[ "$LOU_ALIAS_HAS_LOU" == "true" ]]; then
  echo "  PASS: alias 'Lou' resolves to Lou Winship (${LOU_ALIAS_NAMES})"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: alias 'Lou' does NOT resolve to Lou Winship (got: ${LOU_ALIAS_NAMES})"
  ((IDENTITY_FAIL++))
fi

if [[ "$LOU_ALIAS_HAS_LUIS" == "false" ]]; then
  echo "  PASS: alias 'Lou' does NOT resolve to Luis Juarez"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: alias 'Lou' incorrectly resolves to Luis Juarez (${LOU_ALIAS_NAMES})"
  ((IDENTITY_FAIL++))
fi

# (d) Alias resolution for "Luis" — should match Luis Juarez, not Lou Winship
LUIS_ALIAS=$(api_get "contacts" \
  --data-urlencode "select=name" \
  --data-urlencode "aliases=cs.{Luis}" \
  --data-urlencode "limit=5")
LUIS_ALIAS_NAMES=$(jq -r '[.[].name] | join(", ")' <<<"$LUIS_ALIAS")
LUIS_ALIAS_HAS_LUIS=$(jq '[.[].name] | any(. == "Luis Juarez")' <<<"$LUIS_ALIAS")
LUIS_ALIAS_HAS_LOU=$(jq '[.[].name] | any(. == "Lou Winship")' <<<"$LUIS_ALIAS")

if [[ "$LUIS_ALIAS_HAS_LUIS" == "true" ]]; then
  echo "  PASS: alias 'Luis' resolves to Luis Juarez (${LUIS_ALIAS_NAMES})"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: alias 'Luis' does NOT resolve to Luis Juarez (got: ${LUIS_ALIAS_NAMES})"
  ((IDENTITY_FAIL++))
fi

if [[ "$LUIS_ALIAS_HAS_LOU" == "false" ]]; then
  echo "  PASS: alias 'Luis' does NOT resolve to Lou Winship"
  ((IDENTITY_PASS++))
else
  echo "  FAIL: alias 'Luis' incorrectly resolves to Lou Winship (${LUIS_ALIAS_NAMES})"
  ((IDENTITY_FAIL++))
fi

echo ""
echo "  Identity checks: ${IDENTITY_PASS} passed, ${IDENTITY_FAIL} failed"
echo ""

# Machine-parseable summary line
echo "LOU_WINSHIP_REGRESSION call_id=${CALL_ID} spans=${SPAN_COUNT} journal_claims=${CLAIM_COUNT} claims_with_project=${CLAIMS_WITH_PROJECT} claims_no_project=${CLAIMS_NO_PROJECT} belief_claims=${BELIEF_COUNT} review_queue_total=${RQ_COUNT} review_queue_pending=${RQ_PENDING} journal_runs=${RUN_COUNT} runs_success=${RUN_SUCCESS} runs_failed=${RUN_FAILED} identity_pass=${IDENTITY_PASS} identity_fail=${IDENTITY_FAIL} timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo ""
  jq -n \
    --arg call_id "$CALL_ID" \
    --argjson spans "$SPAN_COUNT" \
    --argjson journal_claims "$CLAIM_COUNT" \
    --argjson claims_with_project "$CLAIMS_WITH_PROJECT" \
    --argjson claims_no_project "$CLAIMS_NO_PROJECT" \
    --argjson belief_claims "$BELIEF_COUNT" \
    --argjson review_queue_total "$RQ_COUNT" \
    --argjson review_queue_pending "$RQ_PENDING" \
    --argjson journal_runs "$RUN_COUNT" \
    --argjson runs_success "$RUN_SUCCESS" \
    --argjson runs_failed "$RUN_FAILED" \
    --argjson identity_pass "$IDENTITY_PASS" \
    --argjson identity_fail "$IDENTITY_FAIL" \
    '{call_id: $call_id, spans: $spans, journal_claims: $journal_claims, claims_with_project: $claims_with_project, claims_no_project: $claims_no_project, belief_claims: $belief_claims, review_queue_total: $review_queue_total, review_queue_pending: $review_queue_pending, journal_runs: $journal_runs, runs_success: $runs_success, runs_failed: $runs_failed, identity_pass: $identity_pass, identity_fail: $identity_fail, timestamp: (now | todate)}'
fi
