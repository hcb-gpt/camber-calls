#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <packet.md> [packet2.md ...]" >&2
  exit 1
fi

# Output schema (TSV):
# receipt	status	missing_fields	completes_receipt	resolution	git_proof	verify_proof	real_data_pointer	file
printf 'receipt\tstatus\tmissing_fields\tcompletes_receipt\tresolution\tgit_proof\tverify_proof\treal_data_pointer\tfile\n'

extract_field() {
  local key="$1"
  local file="$2"
  local line
  line="$(grep -m1 -E "(^|[[:space:]])${key}:" "$file" || true)"
  [[ -z "$line" ]] && return 1

  local value="${line#*${key}:}"
  value="${value#"${value%%[![:space:]]*}"}"

  # Token-like keys keep only first value token.
  if [[ "$key" == "RECEIPT" || "$key" == "COMPLETES_RECEIPT" || "$key" == "RESOLUTION" ]]; then
    value="${value%% *}"
  fi

  # Normalize placeholder values as missing.
  if [[ "$value" == "NONE" || "$value" == "UNKNOWN" ]]; then
    value=""
  fi

  printf '%s\n' "$value"
}

for file in "$@"; do
  if [[ ! -f "$file" ]]; then
    printf 'UNKNOWN\tFAIL\tfile_not_found\t\t\t\t\t\t%s\n' "$file"
    continue
  fi

  receipt="$(extract_field "RECEIPT" "$file" || true)"
  completes="$(extract_field "COMPLETES_RECEIPT" "$file" || true)"
  resolution="$(extract_field "RESOLUTION" "$file" || true)"
  git_proof="$(extract_field "GIT_PROOF" "$file" || true)"
  verify_proof="$(extract_field "VERIFY_PROOF" "$file" || true)"
  real_data_pointer="$(extract_field "REAL_DATA_POINTER" "$file" || true)"

  missing=()
  [[ -z "$receipt" ]] && missing+=("receipt")
  [[ -z "$completes" ]] && missing+=("completes_receipt")
  [[ -z "$resolution" ]] && missing+=("resolution")
  [[ -z "$git_proof" ]] && missing+=("git_proof")
  [[ -z "$verify_proof" ]] && missing+=("verify_proof")
  [[ -z "$real_data_pointer" ]] && missing+=("real_data_pointer")

  status="PASS"
  missing_joined="-"
  if [[ ${#missing[@]} -gt 0 ]]; then
    status="FAIL"
    missing_joined="$(IFS=,; echo "${missing[*]}")"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${receipt:-UNKNOWN}" \
    "$status" \
    "$missing_joined" \
    "${completes:-}" \
    "${resolution:-}" \
    "${git_proof:-}" \
    "${verify_proof:-}" \
    "${real_data_pointer:-}" \
    "$file"
done
