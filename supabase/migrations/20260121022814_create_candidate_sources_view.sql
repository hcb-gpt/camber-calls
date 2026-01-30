-- Create queryable view for candidate project sources (P4.3a)
-- Extracts attribution data from journal_runs.config and pipedream_run_logs.meta

CREATE OR REPLACE VIEW v_candidate_sources AS
WITH run_candidates AS (
  -- Extract from journal_runs.config.multiproject_project_ids
  SELECT 
    jr.call_id,
    jr.run_id,
    jr.started_at,
    jsonb_array_elements_text(jr.config->'multiproject_project_ids') as candidate_project_id,
    'journal_runs' as data_source,
    jr.config->>'attribution_method' as source_method,
    NULL::numeric as weight
  FROM journal_runs jr
  WHERE jr.config->'multiproject_project_ids' IS NOT NULL
    AND jsonb_array_length(jr.config->'multiproject_project_ids') > 0
),
claim_candidates AS (
  -- Extract from journal_claims.claim_project_candidates
  SELECT 
    jc.call_id,
    jc.run_id,
    jr.started_at,
    cpc->>'project_id' as candidate_project_id,
    'claim_attribution' as data_source,
    cpc->>'evidence' as source_method,
    (cpc->>'score')::numeric as weight
  FROM journal_claims jc
  JOIN journal_runs jr ON jc.run_id = jr.run_id
  CROSS JOIN LATERAL jsonb_array_elements(jc.claim_project_candidates) as cpc
  WHERE jc.claim_project_candidates IS NOT NULL
)
SELECT 
  call_id,
  run_id,
  started_at,
  candidate_project_id,
  p.name as project_name,
  data_source,
  source_method,
  weight
FROM (
  SELECT * FROM run_candidates
  UNION ALL
  SELECT * FROM claim_candidates
) combined
LEFT JOIN projects p ON combined.candidate_project_id::uuid = p.id
ORDER BY started_at DESC, call_id, weight DESC NULLS LAST;

COMMENT ON VIEW v_candidate_sources IS 'Queryable view of project attribution candidates per call. Sources: journal_runs.config, journal_claims.claim_project_candidates';;
