#!/usr/bin/env bash
set -euo pipefail

# Semantic xref high-signal proof harness.
#
# Purpose:
# - Emit a compact readiness snapshot for vector semantic crossref.
# - Run two semantic probes when prerequisites are satisfied:
#   1) misspelling probe: "Windship" should surface Winship-related claims.
#   2) material-color probe: "mystery white" should not elevate White Residence by color alone.
#
# Usage:
#   scripts/semantic_xref_high_signal_proof.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/load-env.sh" >/dev/null

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "ERROR: DATABASE_URL is required." >&2
  exit 1
fi

PSQL_BIN="${PSQL_PATH:-psql}"
if [[ "${PSQL_BIN}" == */* ]]; then
  [[ -x "${PSQL_BIN}" ]] || { echo "ERROR: psql not executable at ${PSQL_BIN}" >&2; exit 1; }
else
  command -v "${PSQL_BIN}" >/dev/null 2>&1 || { echo "ERROR: psql not found in PATH." >&2; exit 1; }
fi

echo "=== Semantic XREF High-Signal Proof ==="
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

READINESS_SQL=$(cat <<'SQL'
WITH coverage AS (
  SELECT
    COUNT(*) FILTER (WHERE active = true) AS total_active,
    COUNT(*) FILTER (WHERE active = true AND embedding IS NOT NULL) AS embedded_active,
    COUNT(*) FILTER (WHERE active = true AND embedding IS NULL) AS missing_embedding,
    COUNT(*) FILTER (WHERE active = true AND lower(claim_text) LIKE '%winship%') AS winship_mentions,
    COUNT(*) FILTER (WHERE active = true AND lower(claim_text) LIKE '%windship%') AS windship_mentions,
    COUNT(*) FILTER (WHERE active = true AND lower(claim_text) LIKE '%mystery white%') AS mystery_white_mentions
  FROM public.journal_claims
),
rpc_def AS (
  SELECT pg_get_functiondef(p.oid) AS fn_def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'xref_search_journal_claims'
  ORDER BY p.oid DESC
  LIMIT 1
)
SELECT
  COALESCE((SELECT extversion FROM pg_extension WHERE extname='vector'), 'MISSING') AS vector_extversion,
  c.total_active,
  c.embedded_active,
  c.missing_embedding,
  c.winship_mentions,
  c.windship_mentions,
  c.mystery_white_mentions,
  CASE
    WHEN EXISTS (SELECT 1 FROM rpc_def WHERE fn_def ILIKE '%from_number%' OR fn_def ILIKE '%to_number%')
      THEN 'LEGACY_PHONE_COLUMNS'
    ELSE 'OK'
  END AS rpc_phone_filter_status
FROM coverage c;
SQL
)

IFS='|' read -r VECTOR_VERSION TOTAL_ACTIVE EMBEDDED_ACTIVE MISSING_EMBED WINSHIP_MENTIONS WINDSHIP_MENTIONS MYSTERY_WHITE_MENTIONS RPC_STATUS < <(
  "${PSQL_BIN}" "${DATABASE_URL}" -X -A -t -F '|' -v ON_ERROR_STOP=1 -c "${READINESS_SQL}"
)

echo "vector_extversion=${VECTOR_VERSION}"
echo "total_active=${TOTAL_ACTIVE}"
echo "embedded_active=${EMBEDDED_ACTIVE}"
echo "missing_embedding=${MISSING_EMBED}"
echo "winship_mentions=${WINSHIP_MENTIONS}"
echo "windship_mentions=${WINDSHIP_MENTIONS}"
echo "mystery_white_mentions=${MYSTERY_WHITE_MENTIONS}"
echo "rpc_phone_filter_status=${RPC_STATUS}"

if [[ "${RPC_STATUS}" != "OK" ]]; then
  echo ""
  echo "BLOCKED: xref_search_journal_claims is still using legacy phone columns."
  echo "Apply migration: supabase/migrations/20260215154500_fix_xref_search_journal_claims_scope_phone_columns.sql"
  exit 2
fi

if [[ "${EMBEDDED_ACTIVE}" -eq 0 ]]; then
  echo ""
  echo "BLOCKED: no embedded journal_claims rows yet."
  echo "Run journal-embed-backfill first (non-dry-run) after OPENAI_API_KEY is configured."
  exit 3
fi

echo ""
echo "--- Probe A: Windship misspelling semantic lookup ---"
"${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -P pager=off -c "
WITH windship_seed AS (
  SELECT embedding, 'windship_claim_embedding'::text AS seed_source
  FROM public.journal_claims
  WHERE active = true
    AND embedding IS NOT NULL
    AND lower(claim_text) LIKE '%windship%'
  ORDER BY created_at DESC
  LIMIT 1
),
winship_fallback AS (
  SELECT embedding, 'winship_claim_embedding_fallback'::text AS seed_source
  FROM public.journal_claims
  WHERE active = true
    AND embedding IS NOT NULL
    AND lower(claim_text) LIKE '%winship%'
  ORDER BY created_at DESC
  LIMIT 1
),
seed AS (
  SELECT * FROM windship_seed
  UNION ALL
  SELECT * FROM winship_fallback
  WHERE NOT EXISTS (SELECT 1 FROM windship_seed)
),
probe AS (
  SELECT s.seed_source, r.*
  FROM seed s
  CROSS JOIN LATERAL public.xref_search_journal_claims(
    s.embedding,
    NULL,
    NULL,
    10,
    1.0
  ) r
)
SELECT
  probe.seed_source,
  COALESCE(p.name, '<unknown>') AS project_name,
  ROUND(probe.score::numeric, 4) AS score,
  ROUND(probe.distance::numeric, 4) AS distance,
  LEFT(probe.claim_text, 120) AS claim_text
FROM probe
LEFT JOIN public.projects p ON p.id = probe.project_id
ORDER BY probe.score DESC
LIMIT 10;"

echo ""
echo "--- Probe B: Mystery white semantic lookup ---"
"${PSQL_BIN}" "${DATABASE_URL}" -X -v ON_ERROR_STOP=1 -P pager=off -c "
WITH seed AS (
  SELECT embedding
  FROM public.journal_claims
  WHERE active = true
    AND embedding IS NOT NULL
    AND lower(claim_text) LIKE '%mystery white%'
  ORDER BY created_at DESC
  LIMIT 1
),
probe AS (
  SELECT r.*
  FROM seed s
  CROSS JOIN LATERAL public.xref_search_journal_claims(
    s.embedding,
    NULL,
    NULL,
    10,
    1.0
  ) r
)
SELECT
  COALESCE(p.name, '<unknown>') AS project_name,
  ROUND(probe.score::numeric, 4) AS score,
  ROUND(probe.distance::numeric, 4) AS distance,
  CASE
    WHEN lower(COALESCE(p.name, '')) LIKE '%white residence%' THEN 'ALERT_WHITE_RESIDENCE_PRESENT'
    ELSE ''
  END AS white_residence_flag,
  LEFT(probe.claim_text, 120) AS claim_text
FROM probe
LEFT JOIN public.projects p ON p.id = probe.project_id
ORDER BY probe.score DESC
LIMIT 10;"

echo ""
echo "Semantic proof completed."
