#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/load-env.sh" >/dev/null 2>&1 || true
fi

for var in SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY EDGE_SHARED_SECRET; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Missing required env var: ${var}" >&2
    echo "Run: source ${ROOT_DIR}/scripts/load-env.sh" >&2
    exit 2
  fi
done

for cmd in curl jq mktemp; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Missing required command: ${cmd}" >&2
    exit 2
  fi
done

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${1:-${ROOT_DIR}/artifacts/temporal_backtest_report_dev_v1}"
mkdir -p "${OUT_DIR}"

LABELS_JSON="${OUT_DIR}/labels.json"
ROWS_JSON="${OUT_DIR}/rows.json"
METRICS_JSON="${OUT_DIR}/metrics.json"
REPORT_MD="${OUT_DIR}/temporal_backtest_report_dev_v1.md"

echo "== temporal backtest harness =="
echo "out_dir=${OUT_DIR}"

curl -sS "${SUPABASE_URL}/rest/v1/eval_hard_spans?select=span_id,expected_project_id,expected_project_name,difficulty_reason,labeled_at,labeler" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" > "${LABELS_JSON}"

LABEL_COUNT="$(jq 'length' "${LABELS_JSON}")"
if [[ "${LABEL_COUNT}" -eq 0 ]]; then
  echo "ERROR: eval_hard_spans returned 0 rows; cannot build backtest." >&2
  exit 3
fi

TMP_ROWS="$(mktemp)"
trap 'rm -f "${TMP_ROWS}"' EXIT
: > "${TMP_ROWS}"

BASE_URL="${SUPABASE_URL}/functions/v1"

while IFS= read -r span_id; do
  label="$(jq -c --arg sid "${span_id}" '.[] | select(.span_id == $sid)' "${LABELS_JSON}")"
  expected_project_id="$(jq -r '.expected_project_id // ""' <<<"${label}")"
  expected_project_name="$(jq -r '.expected_project_name // ""' <<<"${label}")"
  difficulty_reason="$(jq -r '.difficulty_reason // ""' <<<"${label}")"
  labeled_at="$(jq -r '.labeled_at // ""' <<<"${label}")"

  created_at="$(curl -sS "${SUPABASE_URL}/rest/v1/conversation_spans?select=created_at&id=eq.${span_id}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    | jq -r '.[0].created_at // ""')"

  ctx_resp="$(curl -sS -X POST "${BASE_URL}/context-assembly" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    --data "{\"span_id\":\"${span_id}\"}")"

  ctx_ok="$(jq -r '.ok // false' <<<"${ctx_resp}")"
  if [[ "${ctx_ok}" != "true" ]]; then
    jq -nc \
      --arg span_id "${span_id}" \
      --arg expected_project_id "${expected_project_id}" \
      --arg expected_project_name "${expected_project_name}" \
      --arg difficulty_reason "${difficulty_reason}" \
      --arg labeled_at "${labeled_at}" \
      --arg created_at "${created_at}" \
      --arg error "context_assembly_failed" \
      '{
        span_id: $span_id,
        expected_project_id: (if $expected_project_id == "" then null else $expected_project_id end),
        expected_project_name: (if $expected_project_name == "" then null else $expected_project_name end),
        difficulty_reason: (if $difficulty_reason == "" then null else $difficulty_reason end),
        labeled_at: (if $labeled_at == "" then null else $labeled_at end),
        created_at: (if $created_at == "" then null else $created_at end),
        error: $error
      }' >> "${TMP_ROWS}"
    continue
  fi

  interaction_id="$(jq -r '.context_package.meta.interaction_id // ""' <<<"${ctx_resp}")"
  baseline_project_id=""
  if [[ -n "${interaction_id}" ]]; then
    baseline_project_id="$(curl -sS "${SUPABASE_URL}/rest/v1/interactions?select=project_id&interaction_id=eq.${interaction_id}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      | jq -r '.[0].project_id // ""')"
  fi

  router_payload="$(jq -c '{dry_run: true, context_package: .context_package}' <<<"${ctx_resp}")"
  router_resp="$(curl -sS -X POST "${BASE_URL}/ai-router" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "X-Edge-Secret: ${EDGE_SHARED_SECRET}" \
    --data "${router_payload}")"

  decision="$(jq -r '.decision // "none"' <<<"${router_resp}")"
  new_project_id="$(jq -r '.project_id // ""' <<<"${router_resp}")"
  new_confidence="$(jq -r '.confidence // 0' <<<"${router_resp}")"
  prompt_version="$(jq -r '.prompt_version // ""' <<<"${router_resp}")"
  guardrails_enabled="$(jq -r '.decision_trace.guardrails_enabled // false' <<<"${router_resp}")"
  temporal_flags_json="$(jq -c '.decision_trace.temporal_flags // []' <<<"${router_resp}")"
  temporal_score="$(jq -r '.decision_trace.temporal_support_score // null' <<<"${router_resp}")"
  model_error="$(jq -r '.model_error // false' <<<"${router_resp}")"
  model_disagreement="$(jq -r '.model_disagreement // false' <<<"${router_resp}")"

  jq -nc \
    --arg span_id "${span_id}" \
    --arg interaction_id "${interaction_id}" \
    --arg expected_project_id "${expected_project_id}" \
    --arg expected_project_name "${expected_project_name}" \
    --arg difficulty_reason "${difficulty_reason}" \
    --arg labeled_at "${labeled_at}" \
    --arg created_at "${created_at}" \
    --arg baseline_project_id "${baseline_project_id}" \
    --arg decision "${decision}" \
    --arg new_project_id "${new_project_id}" \
    --argjson new_confidence "${new_confidence}" \
    --arg prompt_version "${prompt_version}" \
    --argjson guardrails_enabled "${guardrails_enabled}" \
    --argjson temporal_flags "${temporal_flags_json}" \
    --argjson temporal_score "${temporal_score}" \
    --argjson model_error "${model_error}" \
    --argjson model_disagreement "${model_disagreement}" \
    '{
      span_id: $span_id,
      interaction_id: (if $interaction_id == "" then null else $interaction_id end),
      expected_project_id: (if $expected_project_id == "" then null else $expected_project_id end),
      expected_project_name: (if $expected_project_name == "" then null else $expected_project_name end),
      difficulty_reason: (if $difficulty_reason == "" then null else $difficulty_reason end),
      labeled_at: (if $labeled_at == "" then null else $labeled_at end),
      created_at: (if $created_at == "" then null else $created_at end),
      baseline_project_id: (if $baseline_project_id == "" then null else $baseline_project_id end),
      baseline_decision: (if $baseline_project_id == "" then "none" else "assign" end),
      baseline_correct: ($baseline_project_id != "" and $expected_project_id != "" and $baseline_project_id == $expected_project_id),
      new_decision: $decision,
      new_project_id: (if $new_project_id == "" then null else $new_project_id end),
      new_confidence: $new_confidence,
      new_correct: ($decision == "assign" and $new_project_id != "" and $expected_project_id != "" and $new_project_id == $expected_project_id),
      new_abstain: ($decision != "assign"),
      prompt_version: (if $prompt_version == "" then null else $prompt_version end),
      guardrails_enabled: $guardrails_enabled,
      temporal_flags: $temporal_flags,
      temporal_support_score: $temporal_score,
      model_error: $model_error,
      model_disagreement: $model_disagreement
    }' >> "${TMP_ROWS}"
done < <(jq -r '.[].span_id' "${LABELS_JSON}")

jq -s '.' "${TMP_ROWS}" > "${ROWS_JSON}"

jq '
  def safe_div($a; $b): if $b == 0 then null else ($a / $b) end;
  def block($arr; $decision_key; $correct_key):
    ($arr | {
      total: length,
      assigns: (map(select(.[$decision_key] == "assign")) | length),
      correct_assigns: (map(select(.[$decision_key] == "assign" and .[$correct_key] == true)) | length),
      false_assigns: (map(select(.[$decision_key] == "assign" and .[$correct_key] != true)) | length),
      abstain: (map(select(.[$decision_key] != "assign")) | length)
    }) as $c |
    $c + {
      precision: safe_div($c.correct_assigns; $c.assigns),
      recall: safe_div($c.correct_assigns; $c.total),
      abstain_rate: safe_div($c.abstain; $c.total)
    };
  def hardneg($arr):
    $arr | map(select((.difficulty_reason // "" | ascii_downcase | test("hard|negative|ambig|weak|conflict|sittler"))));
  def with_eval_time($arr):
    $arr | map(. + {eval_time: (.created_at // .labeled_at // "1970-01-01T00:00:00Z")});
  def holdout($arr):
    (with_eval_time($arr) | sort_by(.eval_time)) as $s |
    ($s | length) as $n |
    (if $n == 0 then []
     else ($n * 0.3 | ceil) as $k
     | ($k | if . < 1 then 1 else . end) as $kk
     | $s[-$kk:]
     end);
  . as $rows |
  ($rows | map(select(.error == null))) as $ok |
  ($ok | holdout(.)) as $holdout |
  ($ok | hardneg(.)) as $hard |
  ($ok | map(select(.baseline_correct != true))) as $baseline_wrong |
  ($ok | map(select(.baseline_correct == true))) as $baseline_right |
  {
    run_utc: (now | todateiso8601),
    sample_size_total: ($rows | length),
    sample_size_ok: ($ok | length),
    sample_size_error: (($rows | length) - ($ok | length)),
    baseline: block($ok; "baseline_decision"; "baseline_correct"),
    new_guardrails: block($ok; "new_decision"; "new_correct"),
    delta: {
      precision: (block($ok; "new_decision"; "new_correct").precision - block($ok; "baseline_decision"; "baseline_correct").precision),
      recall: (block($ok; "new_decision"; "new_correct").recall - block($ok; "baseline_decision"; "baseline_correct").recall),
      abstain_rate: (block($ok; "new_decision"; "new_correct").abstain_rate - block($ok; "baseline_decision"; "baseline_correct").abstain_rate)
    },
    correction_rate: safe_div(($baseline_wrong | map(select(.new_correct == true)) | length); ($baseline_wrong | length)),
    regression_rate: safe_div(($baseline_right | map(select(.new_correct != true)) | length); ($baseline_right | length)),
    hard_negative_slice: {
      size: ($hard | length),
      baseline: block($hard; "baseline_decision"; "baseline_correct"),
      new_guardrails: block($hard; "new_decision"; "new_correct")
    },
    out_of_time_holdout: {
      size: ($holdout | length),
      baseline: block($holdout; "baseline_decision"; "baseline_correct"),
      new_guardrails: block($holdout; "new_decision"; "new_correct")
    },
    failure_buckets: {
      corrected_by_new: ($baseline_wrong | map(select(.new_correct == true) | .span_id)),
      regressed_vs_baseline: ($baseline_right | map(select(.new_correct != true) | .span_id)),
      new_false_assign: ($ok | map(select(.new_decision == "assign" and .new_correct != true) | .span_id)),
      new_abstain: ($ok | map(select(.new_decision != "assign") | .span_id)),
      model_error_spans: ($ok | map(select(.model_error == true) | .span_id))
    },
    prompt_versions_seen: ($ok | map(.prompt_version) | unique),
    temporal_flags_seen: ($ok | map(.temporal_flags[]) | unique)
  }
' "${ROWS_JSON}" > "${METRICS_JSON}"

BASE_PREC="$(jq -r '.baseline.precision // "null"' "${METRICS_JSON}")"
NEW_PREC="$(jq -r '.new_guardrails.precision // "null"' "${METRICS_JSON}")"
BASE_REC="$(jq -r '.baseline.recall // "null"' "${METRICS_JSON}")"
NEW_REC="$(jq -r '.new_guardrails.recall // "null"' "${METRICS_JSON}")"
BASE_ABS="$(jq -r '.baseline.abstain_rate // "null"' "${METRICS_JSON}")"
NEW_ABS="$(jq -r '.new_guardrails.abstain_rate // "null"' "${METRICS_JSON}")"
CORR_RATE="$(jq -r '.correction_rate // "null"' "${METRICS_JSON}")"
REG_RATE="$(jq -r '.regression_rate // "null"' "${METRICS_JSON}")"
HARD_SIZE="$(jq -r '.hard_negative_slice.size' "${METRICS_JSON}")"
HOLD_SIZE="$(jq -r '.out_of_time_holdout.size' "${METRICS_JSON}")"

cat > "${REPORT_MD}" <<EOF
# Temporal Backtest Report (DEV v1)

## Run
- UTC: ${RUN_TS}
- Labels source: \`eval_hard_spans\`
- Total labeled spans: $(jq -r 'length' "${LABELS_JSON}")
- Evaluated spans (successful): $(jq -r '.sample_size_ok' "${METRICS_JSON}")
- Error spans: $(jq -r '.sample_size_error' "${METRICS_JSON}")

## Metrics (Baseline vs New Guardrails)
- Precision: baseline=${BASE_PREC}, new=${NEW_PREC}
- Recall: baseline=${BASE_REC}, new=${NEW_REC}
- Abstain rate: baseline=${BASE_ABS}, new=${NEW_ABS}
- Correction rate on baseline misses: ${CORR_RATE}
- Regression rate on baseline hits: ${REG_RATE}

## Hard-Negative Slice
- Size: ${HARD_SIZE}
- Metrics: see \`${METRICS_JSON}\` (\`.hard_negative_slice\`)

## Out-of-Time Holdout
- Split policy: most recent 30% by \`created_at\` (fallback \`labeled_at\`)
- Holdout size: ${HOLD_SIZE}
- Metrics: see \`${METRICS_JSON}\` (\`.out_of_time_holdout\`)

## Failure Buckets
- Corrected by new: $(jq -r '.failure_buckets.corrected_by_new | length' "${METRICS_JSON}")
- Regressed vs baseline: $(jq -r '.failure_buckets.regressed_vs_baseline | length' "${METRICS_JSON}")
- New false-assign: $(jq -r '.failure_buckets.new_false_assign | length' "${METRICS_JSON}")
- New abstain: $(jq -r '.failure_buckets.new_abstain | length' "${METRICS_JSON}")

## Repro Commands
\`\`\`bash
bash scripts/temporal_backtest_harness.sh
jq . artifacts/temporal_backtest_report_dev_v1/metrics.json
\`\`\`

## Artifacts
- Rows: \`${ROWS_JSON}\`
- Metrics: \`${METRICS_JSON}\`
- Labels snapshot: \`${LABELS_JSON}\`
EOF

echo "wrote: ${ROWS_JSON}"
echo "wrote: ${METRICS_JSON}"
echo "wrote: ${REPORT_MD}"
