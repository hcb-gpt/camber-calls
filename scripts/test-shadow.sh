#!/bin/bash
# Simple shadow test - one call at a time
set -euo pipefail

cd "/Users/chadbarlow/gh/hcb-gpt/Beside v3.8"
source .env.local

IID="$1"
SHADOW_ID="${2:-cll_SHADOW_001}"
PIPEDREAM_URL="https://eopz0oyin0j45bv.m.pipedream.net"

echo "Fetching $IID..."

# Fetch and transform in one go
curl -s "${SUPABASE_URL}/rest/v1/calls_raw?interaction_id=eq.${IID}&select=interaction_id,transcript,event_at_utc,direction,owner_phone,other_party_phone" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  | jq -c --arg sid "$SHADOW_ID" '.[0] | . + {interaction_id: $sid, source: "shadow_test"}' \
  > /tmp/shadow_payload.json

echo "Payload size: $(wc -c < /tmp/shadow_payload.json) bytes"
echo "Sending to pipedream..."

curl -s -X POST "$PIPEDREAM_URL" \
  -H "Content-Type: application/json" \
  -d @/tmp/shadow_payload.json

echo ""
