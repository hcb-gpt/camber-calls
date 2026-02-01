#!/usr/bin/env bash
# invariant_gates.sh - CI hard-fail gate checks
#
# Big Rock 1: Non-bypassable invariant enforcement
# Source: STRAT TURN:85 tasking
#
# Usage: ./scripts/invariant_gates.sh [options]
#
# Options:
#   --verbose, -v     Print detailed output including violations
#   --json            Output raw JSON (for CI parsing)
#   --help, -h        Show this help message
#
# Exit codes:
#   0 = ALL GATES PASS
#   1 = ONE OR MORE GATES FAIL
#   2 = ERROR (config/network)

set -euo pipefail

# ============================================================
# LOAD CREDENTIALS
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try central credential loader first
if [[ -f "$HOME/.camber/load-credentials.sh" ]]; then
  source "$HOME/.camber/load-credentials.sh" 2>/dev/null || true
fi

# Fallback to local load-env.sh
if [[ -z "${SUPABASE_URL:-}" ]] && [[ -f "$SCRIPT_DIR/load-env.sh" ]]; then
  source "$SCRIPT_DIR/load-env.sh"
fi

# Verify required env vars
for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: $var" >&2
    echo "Run: source ~/.camber/load-credentials.sh" >&2
    exit 2
  fi
done

# ============================================================
# DEFAULTS
# ============================================================
VERBOSE=false
JSON_OUTPUT=false

# ============================================================
# PARSE ARGS
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help|-h)
      head -20 "$0" | tail -18
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# ============================================================
# RUN GATES
# ============================================================
RESULT=$(curl -s "${SUPABASE_URL}/rest/v1/rpc/ci_run_all_gates" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" 2>/dev/null)

# Check for error response
if echo "$RESULT" | jq -e '.code' >/dev/null 2>&1; then
  echo "ERROR: Database query failed" >&2
  echo "$RESULT" | jq -r '.message // .hint // "Unknown error"' >&2
  exit 2
fi

# ============================================================
# OUTPUT
# ============================================================
if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$RESULT"
else
  echo "=============================================="
  echo "CI INVARIANT GATES"
  echo "=============================================="
  echo ""

  # Process each gate
  FAIL_COUNT=0
  while IFS= read -r gate; do
    GATE_NAME=$(echo "$gate" | jq -r '.gate_name')
    GATE_STATUS=$(echo "$gate" | jq -r '.gate_status')
    VIOLATION_COUNT=$(echo "$gate" | jq -r '.violation_count')

    if [[ "$GATE_STATUS" == "PASS" ]]; then
      echo "✅ $GATE_NAME: PASS"
    else
      echo "❌ $GATE_NAME: FAIL ($VIOLATION_COUNT violations)"
      FAIL_COUNT=$((FAIL_COUNT + 1))

      if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "   First 5 violations:"
        echo "$gate" | jq -r '.violations[:5][] | "   - \(.interaction_id // .span_id)"'
        echo ""
      fi
    fi
  done < <(echo "$RESULT" | jq -c '.[]')

  echo ""
  echo "=============================================="

  if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "RESULT: ❌ FAIL ($FAIL_COUNT gate(s) violated)"
    echo ""
    echo "To see violations: ./scripts/invariant_gates.sh --verbose"
    echo "To get raw JSON:   ./scripts/invariant_gates.sh --json"
    echo ""
    echo "Common fixes:"
    echo "  multi_span_required: Run admin-reseed on affected interactions"
    echo "  no_gap:              Check segment-llm boundary logic"
    echo "  no_uncovered:        Run ai-router or create review items"
    echo "  no_double_covered:   Resolve pending reviews for attributed spans"
    exit 1
  else
    echo "RESULT: ✅ ALL GATES PASS"
    exit 0
  fi
fi

# If JSON output, check for failures
if [[ "$JSON_OUTPUT" == "true" ]]; then
  FAIL_COUNT=$(echo "$RESULT" | jq '[.[] | select(.gate_status == "FAIL")] | length')
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
  fi
fi
