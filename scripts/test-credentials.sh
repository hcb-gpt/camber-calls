#!/bin/bash
# Test credential loading

echo "Testing CAMBER credential system..."
echo ""

# Test central loader
echo "1. Testing central loader (~/.camber/load-credentials.sh)"
source ~/.camber/load-credentials.sh
echo ""

# Verify all required vars
echo "2. Verifying required variables:"
VARS="SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET ANTHROPIC_API_KEY OPENAI_API_KEY"
ALL_GOOD=true

for VAR in $VARS; do
    if [ -n "${!VAR}" ]; then
        echo "   ✅ $VAR (${!VAR:0:30}...)"
    else
        echo "   ❌ $VAR (NOT SET)"
        ALL_GOOD=false
    fi
done

echo ""

# Test API call
echo "3. Testing Supabase API access:"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${SUPABASE_URL}/rest/v1/" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}")

if [ "$RESPONSE" = "200" ]; then
    echo "   ✅ Supabase API accessible (HTTP $RESPONSE)"
else
    echo "   ❌ Supabase API error (HTTP $RESPONSE)"
    ALL_GOOD=false
fi

echo ""

if [ "$ALL_GOOD" = true ]; then
    echo "✅ ALL TESTS PASSED - Credentials working!"
    exit 0
else
    echo "❌ SOME TESTS FAILED - Check configuration"
    exit 1
fi
