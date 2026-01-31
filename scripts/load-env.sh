#!/usr/bin/env bash
# load-env.sh - Central credential loader for Beside v3.8
# REQUIRED: Source this at the start of every script that needs credentials
#
# Usage:
#   source "$(git rev-parse --show-toplevel)/scripts/load-env.sh"
#
# Loads credentials from (in order of precedence):
#   1. Already-set environment variables (no-op if present)
#   2. ~/.camber/load-credentials.sh (team standard)
#   3. ~/.zshrc / ~/.bashrc (fallback)
#   4. .env file in repo root (local dev only, gitignored)
#
# Required vars:
#   SUPABASE_URL
#   SUPABASE_SERVICE_ROLE_KEY
#   EDGE_SHARED_SECRET
#   SUPABASE_DB_URL (optional, for psql access)

set -euo pipefail

_LOAD_ENV_VERSION="v1.0.0"

# Detect repo root
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Track which vars we need
_REQUIRED_VARS=(
  "SUPABASE_URL"
  "SUPABASE_SERVICE_ROLE_KEY"
  "EDGE_SHARED_SECRET"
)

_OPTIONAL_VARS=(
  "SUPABASE_DB_URL"
)

# Check if all required vars are already set
_all_set() {
  for var in "${_REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      return 1
    fi
  done
  return 0
}

# Load from camber credentials (team standard)
_load_camber() {
  local camber_loader="${HOME}/.camber/load-credentials.sh"
  if [[ -f "$camber_loader" ]]; then
    # shellcheck source=/dev/null
    source "$camber_loader"
    return 0
  fi
  return 1
}

# Load from shell rc (fallback)
_load_shell_rc() {
  if [[ -n "${ZSH_VERSION:-}" && -f "${HOME}/.zshrc" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.zshrc" 2>/dev/null || true
  elif [[ -f "${HOME}/.bashrc" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.bashrc" 2>/dev/null || true
  fi
}

# Load from .env file (local dev)
_load_dotenv() {
  local dotenv="${REPO_ROOT}/.env"
  if [[ -f "$dotenv" ]]; then
    # shellcheck source=/dev/null
    set -a
    source "$dotenv"
    set +a
    return 0
  fi
  return 1
}

# Main loading logic
_load_credentials() {
  # Already set? Done.
  if _all_set; then
    return 0
  fi

  # Try camber loader first
  if _load_camber && _all_set; then
    return 0
  fi

  # Try shell rc
  _load_shell_rc
  if _all_set; then
    return 0
  fi

  # Try .env file
  if _load_dotenv && _all_set; then
    return 0
  fi

  # Still missing? Report which ones
  local missing=()
  for var in "${_REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required credentials: ${missing[*]}" >&2
    echo "Fix: Add to ~/.camber/load-credentials.sh or ~/.zshrc" >&2
    return 1
  fi
}

# Run the loader
_load_credentials

# Export for subprocesses
export SUPABASE_URL
export SUPABASE_SERVICE_ROLE_KEY
export EDGE_SHARED_SECRET
export SUPABASE_DB_URL="${SUPABASE_DB_URL:-}"
