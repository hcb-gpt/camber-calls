#!/usr/bin/env bash
# test-credentials.sh - Verify all required credentials are loaded and valid
# REQUIRED: Run before any pipeline work (local or CI)
#
# Usage:
#   ./scripts/test-credentials.sh
#
# Output:
#   PASS: credentials_test | SUPABASE_URL=ok | SERVICE_KEY=ok | EDGE_SECRET=ok | DB_URL=ok | ts=<iso>
#   or
#   FAIL: credentials_test | missing=<var1,var2> | ts=<iso>
#
# Exit codes:
#   0 = PASS
#   1 = FAIL (missing or invalid credentials)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load credentials using central loader
# shellcheck source=load-env.sh
source "${SCRIPT_DIR}/load-env.sh" 2>/dev/null || true

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Check required vars
missing=()
checks=()

# SUPABASE_URL
if [[ -n "${SUPABASE_URL:-}" ]]; then
  # Validate format (should be https://*.supabase.co)
  if [[ "$SUPABASE_URL" =~ ^https://.*\.supabase\.co$ ]]; then
    checks+=("SUPABASE_URL=ok")
  else
    checks+=("SUPABASE_URL=invalid_format")
    missing+=("SUPABASE_URL")
  fi
else
  checks+=("SUPABASE_URL=missing")
  missing+=("SUPABASE_URL")
fi

# SUPABASE_SERVICE_ROLE_KEY
if [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  # Validate length (service role keys are ~200+ chars)
  if [[ ${#SUPABASE_SERVICE_ROLE_KEY} -gt 100 ]]; then
    checks+=("SERVICE_KEY=ok")
  else
    checks+=("SERVICE_KEY=too_short")
    missing+=("SUPABASE_SERVICE_ROLE_KEY")
  fi
else
  checks+=("SERVICE_KEY=missing")
  missing+=("SUPABASE_SERVICE_ROLE_KEY")
fi

# EDGE_SHARED_SECRET
if [[ -n "${EDGE_SHARED_SECRET:-}" ]]; then
  # Validate length (should be 32+ chars)
  if [[ ${#EDGE_SHARED_SECRET} -ge 32 ]]; then
    checks+=("EDGE_SECRET=ok")
  else
    checks+=("EDGE_SECRET=too_short")
    missing+=("EDGE_SHARED_SECRET")
  fi
else
  checks+=("EDGE_SECRET=missing")
  missing+=("EDGE_SHARED_SECRET")
fi

# SUPABASE_DB_URL (optional but check if present)
if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  if [[ "$SUPABASE_DB_URL" =~ ^postgres:// ]]; then
    checks+=("DB_URL=ok")
  else
    checks+=("DB_URL=invalid_format")
  fi
else
  checks+=("DB_URL=not_set")
fi

# Build output
check_str="$(IFS=' | '; echo "${checks[*]}")"

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "PASS: credentials_test | ${check_str} | ts=${TS}"
  exit 0
else
  missing_str="$(IFS=','; echo "${missing[*]}")"
  echo "FAIL: credentials_test | missing=${missing_str} | ${check_str} | ts=${TS}"
  exit 1
fi
