#!/usr/bin/env bash
# replay_call.sh - End-to-end pipeline test for a single interaction
#
# STRAT TURN 72: taskpack=dev_integrator_1
# Usage: ./scripts/replay_call.sh <interaction_id> [options]
#
# Options:
#   --reseed          Run reseed (rechunk) only
#   --reroute         Run reroute only
#   --reseed --reroute  Run both (default)
#   --only-chunk      Alias for --reseed
#   --only-reroute    Alias for --reroute
#   --verbose         Print detailed logs (quiet by default)
#   --save-artifacts  Save raw outputs to /tmp/proofs/<interaction_id>/
#
# Requires env vars:
#   SUPABASE_URL
#   SUPABASE_SERVICE_ROLE_KEY
#   EDGE_SHARED_SECRET
#
# Exit codes:
#   0 = PASS
#   1 = FAIL
#   2 = ERROR (config/network)

set -euo pipefail

# ============================================================
# DEFAULTS
# ============================================================
VERBOSE=false
SAVE_ARTIFACTS=false
DO_RESEED=false
DO_REROUTE=false
INTERACTION_ID=""
MAX_RETRIES=3
RETRY_DELAY=2

# ============================================================
# PARSE ARGS
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --save-artifacts)
      SAVE_ARTIFACTS=true
      shift
      ;;
    --reseed|--only-chunk)
      DO_RESEED=true
      shift
      ;;
    --reroute|--only-reroute)
      DO_REROUTE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 <interaction_id> [--reseed] [--reroute] [--verbose] [--save-artifacts]"
      echo ""
      echo "Options:"
      echo "  --reseed, --only-chunk    Run rechunking only"
      echo "  --reroute, --only-reroute Run rerouting only"
      echo "  --verbose, -v             Print detailed logs"
      echo "  --save-artifacts          Save outputs to /tmp/proofs/<id>/"
      echo ""
      echo "Default: --reseed --reroute (both)"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$INTERACTION_ID" ]]; then
        INTERACTION_ID="$1"
      fi
      shift
      ;;
  esac
done

# Default: both reseed and reroute
if [[ "$DO_RESEED" == "false" && "$DO_REROUTE" == "false" ]]; then
  DO_RESEED=true
  DO_REROUTE=true
fi

# ============================================================
# VALIDATION
# ============================================================
if [[ -z "$INTERACTION_ID" ]]; then
  echo "Usage: $0 <interaction_id> [--reseed] [--reroute] [--verbose]" >&2
  exit 2
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing env var: $var" >&2
    exit 2
  fi
done

# ============================================================
# HELPERS
# ============================================================
log() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[$(date -u +%H:%M:%S)] $*"
  fi
}

log_always() {
  echo "$*"
}

# Retry with exponential backoff on 5xx
curl_with_retry() {
  local url="$1"
  local data="$2"
  local timeout="${3:-180}"
  local attempt=1
  local delay=$RETRY_DELAY
  local result=""
  local http_code=""

  while [[ $attempt -le $MAX_RETRIES ]]; do
    # Get response with http code
    result=$(curl -s --max-time "$timeout" -w "\n%{http_code}" -X POST "$url" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
      -H "X-Source: admin-reseed" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -d "$data" 2>/dev/null || echo -e "\n000")

    # Split response body and http code
    http_code=$(echo "$result" | tail -n1)
    result=$(echo "$result" | sed '$d')

    # Success or client error (don't retry 4xx)
    if [[ "$http_code" =~ ^[23] ]] || [[ "$http_code" =~ ^4 ]]; then
      echo "$result"
      return 0
    fi

    # 5xx or network error - retry
    log "  Attempt $attempt failed (HTTP $http_code), retrying in ${delay}s..."
    sleep "$delay"
    ((attempt++))
    delay=$((delay * 2))
  done

  echo '{"ok":false,"error":"max_retries_exceeded","http_code":"'"$http_code"'"}'
  return 1
}

# ============================================================
# ARTIFACT SETUP
# ============================================================
ARTIFACT_DIR="/tmp/proofs/${INTERACTION_ID}"
if [[ "$SAVE_ARTIFACTS" == "true" ]]; then
  mkdir -p "$ARTIFACT_DIR"
  log "Artifacts will be saved to: $ARTIFACT_DIR"
fi

# ============================================================
# STEP 1: ADMIN-RESEED (if requested)
# ============================================================
IDEMPOTENCY_KEY="replay-$(date -u +%Y%m%dT%H%M%S)-$$"

if [[ "$DO_RESEED" == "true" || "$DO_REROUTE" == "true" ]]; then
  # Determine mode
  if [[ "$DO_RESEED" == "true" && "$DO_REROUTE" == "true" ]]; then
    MODE="resegment_and_reroute"
  elif [[ "$DO_RESEED" == "true" ]]; then
    MODE="resegment_only"
  else
    MODE="reroute_only"
  fi

  log "Step 1: admin-reseed (mode=$MODE)"

  RESEED_RESULT=$(curl_with_retry \
    "${SUPABASE_URL}/functions/v1/admin-reseed" \
    "{\"interaction_id\":\"${INTERACTION_ID}\",\"mode\":\"${MODE}\",\"idempotency_key\":\"${IDEMPOTENCY_KEY}\",\"reason\":\"replay_call.sh\"}" \
    180)

  if [[ "$SAVE_ARTIFACTS" == "true" ]]; then
    echo "$RESEED_RESULT" > "$ARTIFACT_DIR/reseed_response.json"
  fi

  RESEED_OK=$(echo "$RESEED_RESULT" | jq -r '.ok // .receipt.ok // false')

  if [[ "$RESEED_OK" != "true" ]]; then
    RESEED_ERROR=$(echo "$RESEED_RESULT" | jq -r '.error // .receipt.status // "unknown"')
    log_always "FAIL | $INTERACTION_ID | reseed_error=$RESEED_ERROR"
    if [[ "$VERBOSE" == "true" ]]; then
      echo "$RESEED_RESULT" | jq . 2>/dev/null || echo "$RESEED_RESULT"
    fi
    exit 1
  fi

  log "  -> reseed OK"
fi

# ============================================================
# STEP 2: SCOREBOARD
# ============================================================
log "Step 2: Fetching scoreboard"

SCOREBOARD=$(curl_with_retry \
  "${SUPABASE_URL}/rest/v1/rpc/proof_interaction_scoreboard" \
  "{\"p_interaction_id\":\"${INTERACTION_ID}\"}" \
  30)

if [[ "$SAVE_ARTIFACTS" == "true" ]]; then
  echo "$SCOREBOARD" > "$ARTIFACT_DIR/scoreboard.json"
fi

# Parse scoreboard
GENERATION=$(echo "$SCOREBOARD" | jq -r '.[0].generation // 0')
SPANS_ACTIVE=$(echo "$SCOREBOARD" | jq -r '.[0].spans_active // 0')
ATTRIBUTIONS=$(echo "$SCOREBOARD" | jq -r '.[0].attributions // 0')
REVIEW_PENDING=$(echo "$SCOREBOARD" | jq -r '.[0].review_queue_pending // 0')
REVIEW_GAP=$(echo "$SCOREBOARD" | jq -r '.[0].review_queue_gap // 0')
RESEEDS=$(echo "$SCOREBOARD" | jq -r '.[0].override_reseeds // 0')
STATUS=$(echo "$SCOREBOARD" | jq -r '.[0].status // "unknown"')

# ============================================================
# OUTPUT: SINGLE LINE SCOREBOARD
# ============================================================
SCOREBOARD_LINE="$STATUS | $INTERACTION_ID | gen=$GENERATION spans=$SPANS_ACTIVE attr=$ATTRIBUTIONS review=$REVIEW_PENDING gap=$REVIEW_GAP reseeds=$RESEEDS"

log_always "$SCOREBOARD_LINE"

if [[ "$SAVE_ARTIFACTS" == "true" ]]; then
  log_always "Artifacts: $ARTIFACT_DIR/"
fi

# ============================================================
# VERBOSE: DETAILED OUTPUT
# ============================================================
if [[ "$VERBOSE" == "true" ]]; then
  echo ""
  echo "=============================================="
  echo "SCOREBOARD: $INTERACTION_ID"
  echo "=============================================="
  printf "%-25s %s\n" "generation:" "$GENERATION"
  printf "%-25s %s\n" "spans_active:" "$SPANS_ACTIVE"
  printf "%-25s %s\n" "attributions:" "$ATTRIBUTIONS"
  printf "%-25s %s\n" "review_queue_pending:" "$REVIEW_PENDING"
  printf "%-25s %s\n" "review_queue_gap:" "$REVIEW_GAP"
  printf "%-25s %s\n" "override_reseeds:" "$RESEEDS"
  printf "%-25s %s\n" "status:" "$STATUS"
  echo "=============================================="
fi

# ============================================================
# EXIT
# ============================================================
if [[ "$STATUS" == "PASS" ]]; then
  exit 0
else
  exit 1
fi
