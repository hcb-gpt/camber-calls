#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  scripts/gt_rerun_proof_harness.sh --phase <before|after> --outdir <path> <interaction_id> [interaction_id ...]

Examples:
  scripts/gt_rerun_proof_harness.sh --phase before --outdir /Users/chadbarlow/Desktop/gt_rerun_proof_harness_20260215T220000Z \
    cll_06E3HEWTR5RDD39AJK7PZ8G4X8 cll_06E3HS7S75RQK080ZN7K9Q84B0 cll_06E3HG24Q9YM7BGK44NCQRV2Z8

  scripts/gt_rerun_proof_harness.sh --phase after --outdir /Users/chadbarlow/Desktop/gt_rerun_proof_harness_20260215T220000Z \
    cll_06E3HEWTR5RDD39AJK7PZ8G4X8 cll_06E3HS7S75RQK080ZN7K9Q84B0 cll_06E3HG24Q9YM7BGK44NCQRV2Z8
USAGE
}

PHASE=""
OUTDIR=""
INTERACTIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    --outdir)
      OUTDIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      INTERACTIONS+=("$1")
      shift
      ;;
  esac
done

if [[ "$PHASE" != "before" && "$PHASE" != "after" ]]; then
  echo "ERROR: --phase must be before or after" >&2
  usage
  exit 1
fi

if [[ -z "$OUTDIR" ]]; then
  echo "ERROR: --outdir is required" >&2
  usage
  exit 1
fi

if [[ ${#INTERACTIONS[@]} -eq 0 ]]; then
  echo "ERROR: at least one interaction_id is required" >&2
  usage
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL not set after loading env" >&2
  exit 1
fi

PSQL_BIN="${PSQL_PATH:-psql}"
if [[ "${PSQL_BIN}" == */* ]]; then
  if [[ ! -x "${PSQL_BIN}" ]]; then
    echo "ERROR: psql not executable at PSQL_PATH=${PSQL_BIN}" >&2
    exit 1
  fi
elif ! command -v "${PSQL_BIN}" >/dev/null 2>&1; then
  echo "ERROR: psql not found in PATH (or set PSQL_PATH)" >&2
  exit 1
fi

run_copy() {
  local sql="$1"
  local out_file="$2"
  "${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -P pager=off \
    -c "\\copy (${sql}) TO STDOUT WITH CSV HEADER DELIMITER E'\\t'" > "${out_file}"
}

mkdir -p "${OUTDIR}/${PHASE}" "${OUTDIR}/meta"

TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MANIFEST="${OUTDIR}/meta/manifest_${PHASE}.txt"
{
  echo "phase=${PHASE}"
  echo "generated_at_utc=${TIMESTAMP_UTC}"
  echo "outdir=${OUTDIR}"
  echo "interaction_count=${#INTERACTIONS[@]}"
  echo "interactions=${INTERACTIONS[*]}"
} > "${MANIFEST}"

for iid in "${INTERACTIONS[@]}"; do
  if [[ ! "${iid}" =~ ^cll_[A-Za-z0-9]+$ ]]; then
    echo "ERROR: invalid interaction_id format: ${iid}" >&2
    exit 1
  fi

  IID_DIR="${OUTDIR}/${PHASE}/${iid}"
  mkdir -p "${IID_DIR}"

  run_copy "
    select
      span_index,
      id as span_id,
      is_superseded,
      segment_generation,
      char_start,
      char_end,
      word_count,
      segmenter_version,
      created_at
    from conversation_spans
    where interaction_id = '${iid}'
    order by span_index, created_at, id
  " "${IID_DIR}/conversation_spans.tsv"

  run_copy "
    select
      cs.span_index,
      sa.span_id,
      sa.project_id,
      p.name as project_name,
      sa.decision,
      sa.confidence,
      sa.prompt_version,
      sa.model_id,
      sa.attribution_lock,
      sa.attributed_at
    from span_attributions sa
    join conversation_spans cs on cs.id = sa.span_id
    left join projects p on p.id = sa.project_id
    where cs.interaction_id = '${iid}'
    order by cs.span_index, sa.attributed_at nulls last, sa.id
  " "${IID_DIR}/span_attributions.tsv"

  run_copy "
    select
      coalesce(jc.claim_project_id_norm, jc.claim_project_id, jc.project_id) as project_id,
      p.name as project_name,
      count(*)::int as claim_count,
      count(*) filter (where jc.active)::int as active_claim_count
    from journal_claims jc
    left join projects p on p.id = coalesce(jc.claim_project_id_norm, jc.claim_project_id, jc.project_id)
    where jc.call_id = '${iid}'
    group by 1,2
    order by claim_count desc, project_id
  " "${IID_DIR}/journal_claims_by_project.tsv"

  run_copy "
    with span_stats as (
      select
        count(*)::int as spans_total,
        count(*) filter (where not is_superseded)::int as spans_active,
        coalesce(max(segment_generation), 0)::int as max_generation
      from conversation_spans
      where interaction_id = '${iid}'
    ),
    attribution_stats as (
      select count(*)::int as attributions_total
      from span_attributions sa
      join conversation_spans cs on cs.id = sa.span_id
      where cs.interaction_id = '${iid}'
    ),
    journal_stats as (
      select count(*)::int as journal_claims_total
      from journal_claims
      where call_id = '${iid}'
    )
    select
      '${iid}'::text as interaction_id,
      span_stats.spans_total,
      span_stats.spans_active,
      span_stats.max_generation,
      attribution_stats.attributions_total,
      journal_stats.journal_claims_total
    from span_stats
    cross join attribution_stats
    cross join journal_stats
  " "${IID_DIR}/summary.tsv"
done

if [[ "${PHASE}" == "after" && -d "${OUTDIR}/before" ]]; then
  DIFF_DIR="${OUTDIR}/diff"
  mkdir -p "${DIFF_DIR}"
  DIFF_SUMMARY="${DIFF_DIR}/diff_summary.txt"
  : > "${DIFF_SUMMARY}"

  for iid in "${INTERACTIONS[@]}"; do
    for section in conversation_spans span_attributions journal_claims_by_project summary; do
      BEFORE_FILE="${OUTDIR}/before/${iid}/${section}.tsv"
      AFTER_FILE="${OUTDIR}/after/${iid}/${section}.tsv"
      DIFF_FILE="${DIFF_DIR}/${iid}__${section}.diff"

      if [[ ! -f "${BEFORE_FILE}" || ! -f "${AFTER_FILE}" ]]; then
        echo "${iid}\t${section}\tMISSING_BEFORE_OR_AFTER" >> "${DIFF_SUMMARY}"
        continue
      fi

      if diff -u "${BEFORE_FILE}" "${AFTER_FILE}" > "${DIFF_FILE}"; then
        rm -f "${DIFF_FILE}"
        echo "${iid}\t${section}\tNO_CHANGE" >> "${DIFF_SUMMARY}"
      else
        echo "${iid}\t${section}\tCHANGED\t${DIFF_FILE}" >> "${DIFF_SUMMARY}"
      fi
    done
  done
fi

echo "GT harness snapshot complete: phase=${PHASE} outdir=${OUTDIR}"
