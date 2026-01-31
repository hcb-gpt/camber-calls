#!/bin/bash
# shadow-batch.sh - Run shadow tests through v3.8.8 pipeline
# Usage: ./shadow-batch.sh [interaction_ids_file]
#
# Fetches payloads from calls_raw, sends to pipedream with cll_SHADOW_ prefix
# Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY in environment or .env.local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Load credentials (REQUIRED PROTOCOL)
source "${SCRIPT_DIR}/load-env.sh"

PIPEDREAM_URL="https://eopz0oyin0j45bv.m.pipedream.net"
LOG_FILE="$REPO_DIR/shadow_results_$(date +%Y%m%d_%H%M%S).jsonl"

# Check required vars
if [[ -z "${SUPABASE_URL:-}" ]] || [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required"
  exit 1
fi

# Input file or stdin
INPUT_FILE="${1:-}"
if [[ -n "$INPUT_FILE" ]] && [[ -f "$INPUT_FILE" ]]; then
  IDS=$(cat "$INPUT_FILE")
elif [[ -n "$INPUT_FILE" ]]; then
  # Treat as comma-separated list
  IDS=$(echo "$INPUT_FILE" | tr ',' '\n')
else
  echo "Usage: $0 <interaction_ids_file> OR $0 id1,id2,id3"
  exit 1
fi

echo "Shadow batch runner - v3.8.8"
echo "Results: $LOG_FILE"
echo "---"

COUNT=0
PASS=0
FAIL=0

for IID in $IDS; do
  IID=$(echo "$IID" | tr -d '[:space:]')
  [[ -z "$IID" ]] && continue

  COUNT=$((COUNT + 1))
  SHADOW_ID="cll_SHADOW_$(printf '%03d' $COUNT)"

  echo -n "[$COUNT] $IID -> $SHADOW_ID ... "

  # Fetch from calls_raw via PostgREST
  PAYLOAD=$(curl -s \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    "$SUPABASE_URL/rest/v1/calls_raw?interaction_id=eq.$IID&select=interaction_id,transcript,event_at_utc,direction,owner_phone,other_party_phone" \
    | jq -c '.[0] // empty')

  if [[ -z "$PAYLOAD" ]]; then
    echo "SKIP (not found)"
    echo "{\"shadow_id\":\"$SHADOW_ID\",\"original_id\":\"$IID\",\"status\":\"skip\",\"reason\":\"not_found\"}" >> "$LOG_FILE"
    continue
  fi

  # Build shadow payload
  SHADOW_PAYLOAD=$(echo "$PAYLOAD" | jq -c \
    --arg sid "$SHADOW_ID" \
    '. + {interaction_id: $sid, source: "shadow_batch"}')

  # Send to pipedream
  RESULT=$(curl -s -X POST "$PIPEDREAM_URL" \
    -H "Content-Type: application/json" \
    -d "$SHADOW_PAYLOAD")

  # Parse result
  OK=$(echo "$RESULT" | jq -r '.ok // false')
  PROJECT=$(echo "$RESULT" | jq -r '.project_name // "null"')
  SOURCE=$(echo "$RESULT" | jq -r '.project_source // "null"')

  if [[ "$OK" == "true" ]]; then
    echo "PASS | project=$PROJECT ($SOURCE)"
    PASS=$((PASS + 1))
  else
    ERROR=$(echo "$RESULT" | jq -r '.error // "unknown"')
    echo "FAIL | $ERROR"
    FAIL=$((FAIL + 1))
  fi

  # Log full result
  echo "{\"shadow_id\":\"$SHADOW_ID\",\"original_id\":\"$IID\",\"result\":$RESULT}" >> "$LOG_FILE"

  # Small delay to avoid hammering
  sleep 0.2
done

echo "---"
echo "Done: $COUNT processed, $PASS passed, $FAIL failed"
echo "Results: $LOG_FILE"
