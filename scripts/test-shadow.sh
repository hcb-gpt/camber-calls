#!/bin/bash
# Simple shadow test - one call at a time
set -euo pipefail

cd "/Users/chadbarlow/gh/hcb-gpt/Beside v3.8"
source .env.local

IID="$1"
SHADOW_ID="${2:-cll_SHADOW_001}"
PD_SHADOW_URL="${PD_SHADOW_URL:-}"

if [[ -z "$PD_SHADOW_URL" ]]; then
  echo "ERROR: PD_SHADOW_URL required"
  exit 1
fi

echo "Fetching $IID..."

# Fetch and transform in one go
curl -s "${SUPABASE_URL}/rest/v1/calls_raw?interaction_id=eq.${IID}&select=interaction_id,transcript,event_at_utc,direction,owner_phone,other_party_phone" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  | jq -c --arg sid "$SHADOW_ID" '.[0] | . + {interaction_id: $sid, source: "shadow_test"}' \
  > /tmp/shadow_payload.json

echo "Payload size: $(wc -c < /tmp/shadow_payload.json) bytes"
echo "Sending to shadow endpoint..."

curl -s -X POST "$PD_SHADOW_URL" \
  -H "Content-Type: application/json" \
  -d @/tmp/shadow_payload.json

echo ""
