#!/bin/bash
# Beside v3.8 Environment Loader
# Sources credentials for scripts that need them
# Usage: source scripts/load-env.sh

# Try central location first
if [ -f "$HOME/.camber/credentials.env" ]; then
    set -a
    source "$HOME/.camber/credentials.env"
    set +a
    echo "✅ Loaded credentials from ~/.camber/credentials.env"
# Fallback to local .env.local
elif [ -f "$(git rev-parse --show-toplevel)/.env.local" ]; then
    set -a
    source "$(git rev-parse --show-toplevel)/.env.local"
    set +a
    echo "✅ Loaded credentials from .env.local"
else
    echo "❌ No credentials found!"
    echo "   Expected: ~/.camber/credentials.env"
    echo "   Or: $(git rev-parse --show-toplevel)/.env.local"
    echo ""
    echo "   Setup: cp ~/Desktop/env\ secrets.txt ~/.camber/credentials.env"
    exit 1
fi

# Verify required vars
MISSING=""
[ -z "$SUPABASE_URL" ] && MISSING="$MISSING SUPABASE_URL"
[ -z "$SUPABASE_SERVICE_ROLE_KEY" ] && MISSING="$MISSING SUPABASE_SERVICE_ROLE_KEY"
[ -z "$EDGE_SHARED_SECRET" ] && MISSING="$MISSING EDGE_SHARED_SECRET"

if [ -n "$MISSING" ]; then
    echo "⚠️  Missing required vars:$MISSING"
    exit 1
fi

# Export Supabase CLI token if available
if [ -n "$CLI" ]; then
    export SUPABASE_ACCESS_TOKEN="$CLI"
fi
