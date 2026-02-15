-- Semantic xref high-signal proof SQL.
--
-- Usage:
--   psql "$DATABASE_URL" -f scripts/semantic_xref_high_signal_proof.sql
--
-- Notes:
-- - This script is read-only.
-- - If rpc_phone_filter_status != 'OK', apply:
--   supabase/migrations/20260215154500_fix_xref_search_journal_claims_scope_phone_columns.sql
-- - If embedded_active = 0, run journal-embed-backfill first (non-dry-run).

\echo '=== Section 1: Readiness Snapshot ==='
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

\echo ''
\echo '=== Section 2: Probe A (Windship misspelling) ==='
WITH windship_seed AS (
  SELECT
    embedding,
    claim_text AS seed_query_text,
    'windship_claim_embedding'::text AS seed_source
  FROM public.journal_claims
  WHERE active = true
    AND embedding IS NOT NULL
    AND lower(claim_text) LIKE '%windship%'
  ORDER BY created_at DESC
  LIMIT 1
),
winship_fallback AS (
  SELECT
    embedding,
    claim_text AS seed_query_text,
    'winship_claim_embedding_fallback'::text AS seed_source
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
    1.0,
    s.seed_query_text
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
LIMIT 10;

\echo ''
\echo '=== Section 3: Probe B (mystery white material-color) ==='
WITH seed AS (
  SELECT
    embedding,
    claim_text AS seed_query_text
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
    1.0,
    s.seed_query_text
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
LIMIT 10;
