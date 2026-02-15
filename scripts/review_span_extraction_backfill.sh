#!/usr/bin/env bash
set -euo pipefail

# review_span_extraction_backfill.sh
# Run journal-extract against review-gated spans (confidence >= 0.70) that are
# currently missing journal claims, with optional 363-row sample limits.
#
# Usage:
#   ./scripts/review_span_extraction_backfill.sh
#   ./scripts/review_span_extraction_backfill.sh --all
#   ./scripts/review_span_extraction_backfill.sh --ids-file /tmp/spans.txt
#   ./scripts/review_span_extraction_backfill.sh --dry-run
#
# Input format for --ids-file:
#   interaction_id|span_id|span_index

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"
LOG_DIR="/tmp/review_span_extraction_backfill"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
RUN_ID="run_${TIMESTAMP}"
LOG_FILE="${LOG_DIR}/${RUN_ID}.log"
RESULTS_FILE="${LOG_DIR}/results_${RUN_ID}.csv"
TARGETS_FILE="${LOG_DIR}/targets_${RUN_ID}.csv"

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is required for pre/post proof metrics." >&2
  exit 1
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    exit 1
  fi
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for response parsing. Install jq and retry." >&2
  exit 1
fi

PSQL_BIN="${PSQL_BIN:-psql}"
HAS_PSQL=false
if command -v "${PSQL_BIN}" >/dev/null 2>&1; then
  HAS_PSQL=true
fi
FUNCTION_URL="${SUPABASE_URL}/functions/v1/journal-extract"
BATCH_DELAY_MS="${BATCH_DELAY_MS:-2000}"

LIMIT="${LIMIT:-363}"
DRY_RUN=false
IDS_FILE=""
USE_IDS_FILE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --all)
      LIMIT=0
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --ids-file)
      IDS_FILE="$2"
      USE_IDS_FILE=true
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--limit N] [--all] [--ids-file file] [--dry-run]"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

log() {
  local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

fetch_targets() {
  if [[ "$USE_IDS_FILE" == "true" ]]; then
    if [[ ! -f "$IDS_FILE" ]]; then
      echo "ERROR: ids file not found: $IDS_FILE" >&2
      exit 1
    fi
    awk 'NF {print}' "$IDS_FILE" | sed '/^#/d'
    return
  fi

  if [[ "$HAS_PSQL" == "true" ]]; then
    local limit_clause=""
    if [[ "$LIMIT" -gt 0 ]]; then
      limit_clause="LIMIT ${LIMIT}"
    fi

    "${PSQL_BIN}" "${DATABASE_URL}" -X -A -F'|' -t -v ON_ERROR_STOP=1 <<SQL
WITH candidates AS (
  SELECT
    interaction_id,
    span_id::text AS span_id,
    span_index,
    to_char(attributed_at, 'YYYY-MM-DD HH24:MI:SS') AS attributed_at
  FROM public.v_review_spans_missing_extraction
  ORDER BY attributed_at DESC
  ${limit_clause}
)
SELECT
  interaction_id || '|' || span_id || '|' || span_index AS row_text
FROM candidates;
SQL
    return
  fi

  local response
  local curl_args=(
    "--data-urlencode" "select=interaction_id,span_id,span_index"
    "--data-urlencode" "order=attributed_at.desc"
  )
  if [[ "$LIMIT" -gt 0 ]]; then
    curl_args+=("--data-urlencode" "limit=${LIMIT}")
  fi

  response="$(curl -sS -G "${SUPABASE_URL}/rest/v1/v_review_spans_missing_extraction" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    "${curl_args[@]}" \
    --max-time 120)"

  if [[ -z "$response" ]]; then
    echo "ERROR: empty response from v_review_spans_missing_extraction." >&2
    exit 1
  fi
  if ! jq -e 'type=="array"' <<<"$response" >/dev/null 2>&1; then
    echo "ERROR: invalid REST response for v_review_spans_missing_extraction." >&2
    echo "$response" >&2
    exit 1
  fi

  jq -r '.[] | select(.interaction_id != null and .span_id != null and .span_index != null) | "\(.interaction_id)|\(.span_id)|\(.span_index)"' <<<"$response"
}

collect_metrics() {
  local span_ids="$1"
  local label="$2"

  if [[ "$HAS_PSQL" == "true" ]]; then
    local span_ids_csv="$1"

    "${PSQL_BIN}" "${DATABASE_URL}" -X -A -F' ' -t -v ON_ERROR_STOP=1 <<SQL
WITH targets AS (
  SELECT unnest(ARRAY[${span_ids_csv}])::uuid AS span_id
),
claims AS (
  SELECT
    jc.call_id,
    jc.source_span_id,
    jc.claim_type,
    jc.claim_text,
    jc.char_start,
    jc.char_end,
    jc.pointer_type
  FROM targets t
  JOIN public.journal_claims jc
    ON jc.source_span_id = t.span_id
  WHERE jc.active = true
),
duplicate_keys AS (
  SELECT
    call_id,
    source_span_id,
    claim_type,
    claim_text,
    COUNT(*) AS claims_per_key
  FROM claims
  GROUP BY 1,2,3,4
  HAVING COUNT(*) > 1
)
SELECT
  '${label}' AS metric_label,
  (SELECT COUNT(*) FROM targets) AS target_span_count,
  (SELECT COUNT(*) FROM claims) AS recovered_claim_count_total,
  (SELECT COUNT(*) FROM claims WHERE char_start IS NOT NULL AND char_end IS NOT NULL AND pointer_type = 'transcript_span') AS recovered_claims_with_char_pointer,
  (SELECT COALESCE(SUM(claims_per_key - 1), 0) FROM duplicate_keys) AS duplicate_key_rows;
SQL
    return
  fi

  if [[ -z "$span_ids" ]]; then
    echo "${label} 0 0 0 0"
    return
  fi

  local target_count
  local in_filter
  local response
  local recovered_claim_count_total
  local recovered_claims_with_pointer
  local duplicate_key_rows

  target_count="$(printf '%s' "$span_ids" | awk -F',' 'BEGIN {count=0} NF {count=NF} END {if (count < 0) count=0; print count + 0}')"
  in_filter="$(printf '%s\n' "$span_ids" | tr ',' '\n' | awk 'NF {gsub(/[[:space:]]/, "", $0); if (n++) printf ","; printf "\"%s\"",$0}')"

  response="$(curl -sS -G "${SUPABASE_URL}/rest/v1/journal_claims" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    --data-urlencode "select=call_id,source_span_id,claim_type,claim_text,char_start,char_end,pointer_type" \
    --data-urlencode "active=eq.true" \
    --data-urlencode "source_span_id=in.(${in_filter})" \
    --data-urlencode "limit=200000" \
    --max-time 120)"

  if [[ -z "$response" ]] || ! jq -e 'type=="array"' <<<"$response" >/dev/null 2>&1; then
    echo "${label} ${target_count} 0 0 0"
    return
  fi

  recovered_claim_count_total="$(jq 'length' <<<"$response")"
  recovered_claims_with_pointer="$(jq '[.[] | select(.char_start != null and .char_end != null and .pointer_type == "transcript_span")] | length' <<<"$response")"
  duplicate_key_rows="$(jq '(. | sort_by(.call_id, .source_span_id, .claim_type, .claim_text) | group_by(.call_id, .source_span_id, .claim_type, .claim_text) | map(length - 1) | map(select(. > 0)) | add // 0)' <<<"$response")"
  echo "${label} ${target_count} ${recovered_claim_count_total} ${recovered_claims_with_pointer} ${duplicate_key_rows}"
}

json_field() {
  local body="$1"
  local expression="$2"
  local fallback="$3"
  jq -r "${expression}" <<<"${body}" 2>/dev/null || echo "${fallback}"
}

process_span() {
  local interaction_id="$1"
  local span_id="$2"
  local span_index="$3"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "${interaction_id}|${span_id}|${span_index}|skipped|0|0|dry_run|0" >> "$RESULTS_FILE"
    log "DRY RUN: ${interaction_id} span_id=${span_id}"
    return
  fi

  local payload
  payload="{\"span_id\":\"${span_id}\"}"

  local response
  response="$(curl -s -w "\n%{http_code}" -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    -d "$payload" \
    --max-time 120 2>&1 || true)"

  local http_code
  http_code="$(echo "$response" | tail -n1)"
  local body
  body="$(echo "$response" | sed '$d')"

  local status="error_${http_code}"
  local skipped_reason=""
  local claims_extracted=0
  local claims_written=0
  local ms=0

  if [[ "$http_code" == "200" ]]; then
    claims_extracted="$(json_field "$body" '.claims_extracted // 0' 0)"
    claims_written="$(json_field "$body" '.claims_written // 0' 0)"
    ms="$(json_field "$body" '.ms // 0' 0)"
    skipped_reason="$(json_field "$body" '.reason // empty' '')"
    local idempotent_skip
    idempotent_skip="$(json_field "$body" '.idempotent_skip // false' false)"
    if [[ "$idempotent_skip" == "true" ]]; then
      status="skipped_idempotent"
      skipped_reason="${skipped_reason:-already_processed}"
    elif [[ -n "$skipped_reason" ]]; then
      status="skipped"
    else
      status="ok"
    fi
  else
    if [[ -z "$body" ]]; then
      skipped_reason="no_response_body"
    else
      skipped_reason="$(json_field "$body" '.error // "http_'${http_code}'"' "http_${http_code}")"
    fi
  fi

  echo "${interaction_id}|${span_id}|${span_index}|${status}|${claims_extracted}|${claims_written}|${skipped_reason}|${ms}" >> "$RESULTS_FILE"
  log "(${status}) ${interaction_id} span_index=${span_index} claims=${claims_written}/${claims_extracted} ${skipped_reason:+(${skipped_reason})} ${ms}ms"
}

TARGETS=$(fetch_targets)
if [[ -z "${TARGETS:-}" ]]; then
  echo "No spans matched v_review_spans_missing_extraction (limit=${LIMIT}). Nothing to do." | tee -a "$LOG_FILE"
  exit 0
fi

echo "$TARGETS" > "$TARGETS_FILE"
echo "interaction_id|span_id|span_index|status|claims_extracted|claims_written|skipped_reason|ms" > "$RESULTS_FILE"

SPAN_IDS="$(printf '%s\n' "$TARGETS" \
  | awk -F'|' 'NF>=3 {gsub(/[[:space:]]/, "", $2); if ($2 ~ /^[0-9a-fA-F-]{36}$/) print $2 }' \
  | tr '\n' ',' | sed 's/,$//')"
if [[ -z "$SPAN_IDS" ]]; then
  echo "ERROR: Could not build span-id list from target rows." >&2
  exit 1
fi
if [[ "$HAS_PSQL" == "true" ]]; then
  SPAN_IDS_METRICS="$(printf '%s\n' "$SPAN_IDS" | tr ',' '\n' | awk 'NF {printf "'"'"'%s'"'"'::uuid,",$0}' | sed 's/,$//')"
else
  SPAN_IDS_METRICS="$SPAN_IDS"
fi

PRE_METRICS="$(collect_metrics "$SPAN_IDS_METRICS" pre)"
read -r PRE_LABEL PRE_TOTAL PRE_CLAIMS PRE_PTR_CLAIMS PRE_DUPES <<<"${PRE_METRICS}"

log "=== Review-span extraction backfill start ==="
log "Target spans: ${PRE_TOTAL} (sample=${LIMIT})"
log "Dry run: ${DRY_RUN}"
log "Results CSV: ${RESULTS_FILE}"
log "Targets file: ${TARGETS_FILE}"
log "Log: ${LOG_FILE}"

COUNT=0
TOTAL=$(echo "$TARGETS" | awk 'NF' | wc -l | tr -d ' ')
DELAY_SEC=$(echo "scale=3; $BATCH_DELAY_MS / 1000" | bc)

while IFS='|' read -r interaction_id span_id span_index; do
  [[ -z "$interaction_id" ]] && continue
  COUNT=$((COUNT + 1))
  log "[${COUNT}/${TOTAL}] Processing ${interaction_id} span=${span_index} (${span_id})"
  process_span "$interaction_id" "$span_id" "$span_index"
  if [[ "$COUNT" -lt "$TOTAL" ]]; then
    sleep "$DELAY_SEC"
  fi
done <<< "$TARGETS"

POST_METRICS="$(collect_metrics "$SPAN_IDS_METRICS" post)"
read -r POST_LABEL POST_TOTAL POST_CLAIMS POST_PTR_CLAIMS POST_DUPES <<<"${POST_METRICS}"

log "=== Proof summary ==="
log "pre target_spans=${PRE_TOTAL} recovered_claims=${PRE_CLAIMS} recovered_with_char_pointer=${PRE_PTR_CLAIMS} duplicate_key_rows=${PRE_DUPES}"
log "post target_spans=${POST_TOTAL} recovered_claims=${POST_CLAIMS} recovered_with_char_pointer=${POST_PTR_CLAIMS} duplicate_key_rows=${POST_DUPES}"
log "Delta recovered_claims=${POST_CLAIMS}-${PRE_CLAIMS}; char_pointer=${POST_PTR_CLAIMS}-${PRE_PTR_CLAIMS}; duplicate_key_delta=${POST_DUPES}-${PRE_DUPES}"
log "Done."

echo "REVIEW_SPAN_BACKFILL_RESULT target_span_count=${POST_TOTAL} pre_claims=${PRE_CLAIMS} post_claims=${POST_CLAIMS} pre_claims_with_char_pointer=${PRE_PTR_CLAIMS} post_claims_with_char_pointer=${POST_PTR_CLAIMS} pre_duplicate_keys=${PRE_DUPES} post_duplicate_keys=${POST_DUPES}"
