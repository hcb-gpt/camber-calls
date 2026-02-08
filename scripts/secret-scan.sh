#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/secret-scan.sh --staged
  scripts/secret-scan.sh --diff <git-range>
  scripts/secret-scan.sh --all
EOF
}

mode="${1:---staged}"
range="${2:-}"

extract_added_lines_from_diff() {
  local diff_input="$1"
  printf '%s\n' "$diff_input" | awk '
    /^\+\+\+ b\// { file=$2; sub(/^\+\+\+ b\//, "", file); next }
    /^\+[^+]/ {
      line = substr($0, 2);
      print file ":" line;
    }
  '
}

collect_candidates() {
  case "$mode" in
    --staged)
      extract_added_lines_from_diff "$(git diff --cached --unified=0 --no-color --diff-filter=ACMR)"
      ;;
    --diff)
      if [[ -z "$range" ]]; then
        echo "Missing git range for --diff" >&2
        usage >&2
        exit 2
      fi
      extract_added_lines_from_diff "$(git diff "$range" --unified=0 --no-color --diff-filter=ACMR)"
      ;;
    --all)
      git ls-files | while read -r file; do
        awk -v file="$file" '{ print file ":" $0 }' "$file"
      done
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

list_changed_files() {
  case "$mode" in
    --staged)
      git diff --cached --name-only --diff-filter=ACMR
      ;;
    --diff)
      git diff "$range" --name-only --diff-filter=ACMR
      ;;
    --all)
      git ls-files
      ;;
  esac
}

secret_pattern='(sk-[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|sbp_[A-Za-z0-9_-]{10,}|SUPABASE_SERVICE_ROLE(_KEY)?[[:space:]]*[:=][[:space:]]*["'"'"'"'"'"'"]?[A-Za-z0-9._-]{16,}|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{16,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9._-]{10,}\.[A-Za-z0-9._-]{10,}|[A-Za-z0-9.-]+\.pipedream\.net)'
allowlist_pattern='(\[REDACTED\]|<REDACTED>|YOUR_[A-Z0-9_]+|REPLACE_WITH_[A-Z0-9_]+|EXAMPLE|example|placeholder|DUMMY|TEST_)'

candidates="$(collect_candidates || true)"
changed_files="$(list_changed_files || true)"

tracked_mcp_files="$(printf '%s\n' "$changed_files" | rg -i '(^|/)\.mcp\.json(\.disabled)?$|(^|/).+\.mcp\.json$' || true)"
if [[ -n "$tracked_mcp_files" ]]; then
  echo "secret-scan: tracking MCP credential files is blocked."
  echo "$tracked_mcp_files"
  exit 1
fi

if [[ -z "$candidates" ]]; then
  echo "secret-scan: no candidate lines to scan."
  exit 0
fi

matches="$(printf '%s\n' "$candidates" | rg -i "$secret_pattern" || true)"
filtered_matches="$(printf '%s\n' "$matches" | rg -vi "$allowlist_pattern" || true)"

if [[ -n "$filtered_matches" ]]; then
  echo "secret-scan: potential secret detected. Remove or replace with [REDACTED]."
  echo "$filtered_matches"
  exit 1
fi

echo "secret-scan: no findings."
