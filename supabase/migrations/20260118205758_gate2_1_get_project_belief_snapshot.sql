
-- ============================================
-- G2.1: get_project_belief_snapshot function
-- Per frozen interface v1.1
-- ============================================

CREATE OR REPLACE FUNCTION get_project_belief_snapshot(p_project_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_result JSONB;
  v_claims JSONB;
  v_conflicts JSONB;
  v_assumptions JSONB;
  v_open_loops JSONB;
  v_coverage JSONB;
  v_limits JSONB;
  v_calls_count INT;
  v_calls_start TIMESTAMPTZ;
  v_calls_end TIMESTAMPTZ;
  v_lag_hours NUMERIC;
BEGIN
  -- Size limits per v1.1 spec
  v_limits := jsonb_build_object(
    'max_chars', 6000,
    'max_claims', 20,
    'max_conflicts', 5,
    'max_open_loops', 10,
    'max_assumptions', 5
  );

  -- Coverage: calls processed
  SELECT 
    COUNT(*),
    MIN(event_at_utc),
    MAX(event_at_utc),
    EXTRACT(EPOCH FROM (NOW() - MAX(ingested_at_utc))) / 3600.0
  INTO v_calls_count, v_calls_start, v_calls_end, v_lag_hours
  FROM interactions
  WHERE project_id = p_project_id
    AND channel = 'call';

  -- Coverage: adapters
  v_coverage := jsonb_build_object(
    'calls_processed', jsonb_build_object(
      'range_start_utc', v_calls_start,
      'range_end_utc', v_calls_end,
      'count', COALESCE(v_calls_count, 0),
      'ingestion_lag_hours', ROUND(COALESCE(v_lag_hours, 0)::numeric, 2)
    ),
    'adapters', (
      SELECT jsonb_object_agg(
        adapter_name,
        jsonb_build_object(
          'status', status::text,
          'last_sync_utc', last_sync_utc
        )
      )
      FROM adapter_status
    ),
    'entity_resolution', jsonb_build_object(
      'projects_searched', jsonb_build_array(p_project_id),
      'confidence', 1.0
    ),
    'known_gaps', jsonb_build_array(
      'BuilderTrend finance not yet integrated',
      'Email adapter not built'
    )
  );

  -- Claims: top 20 by relevance (recency × confidence × warrant weight)
  SELECT COALESCE(jsonb_agg(claim_obj ORDER BY relevance_score DESC), '[]'::jsonb)
  INTO v_claims
  FROM (
    SELECT 
      jsonb_build_object(
        'claim_id', bc.id,
        'claim_type', bc.claim_type::text,
        'epistemic_status', bc.epistemic_status::text,
        'warrant_level', bc.warrant_level::text,
        'confidence', bc.confidence,
        'confidence_rationale', bc.confidence_rationale,
        'lifecycle', bc.lifecycle::text,
        'subject_refs', jsonb_build_object(
          'project_id', bc.project_id,
          'contact_id', bc.contact_id,
          'vendor_id', bc.vendor_id
        ),
        'speaker_entity_id', bc.speaker_entity_id,
        'origin_entity_id', bc.origin_entity_id,
        'origin_kind', bc.origin_kind::text,
        'origin_confidence', bc.origin_confidence,
        'event_at_utc', bc.event_at_utc,
        'ingested_at_utc', bc.ingested_at_utc,
        'pointers', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'source_type', cp.source_type::text,
            'source_id', cp.source_id,
            'ts_start', cp.ts_start,
            'ts_end', cp.ts_end
          ))
          FROM claim_pointers cp
          WHERE cp.claim_id = bc.id
        ), '[]'::jsonb),
        'short_text', bc.short_text
      ) AS claim_obj,
      -- Relevance score: recency (days ago inverted) × confidence × warrant weight
      (
        (1.0 / GREATEST(1, EXTRACT(EPOCH FROM (NOW() - bc.event_at_utc)) / 86400.0)) *
        bc.confidence *
        CASE bc.warrant_level 
          WHEN 'execution_accept' THEN 2.0 
          ELSE 1.0 
        END *
        CASE bc.lifecycle
          WHEN 'active' THEN 1.0
          WHEN 'disputed' THEN 0.8
          ELSE 0.3
        END
      ) AS relevance_score
    FROM belief_claims bc
    WHERE bc.project_id = p_project_id
      AND bc.lifecycle IN ('active', 'disputed')
    ORDER BY relevance_score DESC
    LIMIT 20
  ) ranked_claims;

  -- Conflicts: top 5 unresolved
  SELECT COALESCE(jsonb_agg(conflict_obj), '[]'::jsonb)
  INTO v_conflicts
  FROM (
    SELECT jsonb_build_object(
      'conflict_id', bf.id,
      'claim_ids', (
        SELECT jsonb_agg(cc.claim_id)
        FROM conflict_claims cc
        WHERE cc.conflict_id = bf.id
      ),
      'conflict_type', bf.conflict_type::text,
      'status', bf.status::text,
      'summary', bf.summary
    ) AS conflict_obj
    FROM belief_conflicts bf
    WHERE bf.status = 'unresolved'
      AND EXISTS (
        SELECT 1 FROM conflict_claims cc
        JOIN belief_claims bc ON cc.claim_id = bc.id
        WHERE cc.conflict_id = bf.id AND bc.project_id = p_project_id
      )
    ORDER BY bf.created_at DESC
    LIMIT 5
  ) ranked_conflicts;

  -- Assumptions: top 5 most recent, not expired
  SELECT COALESCE(jsonb_agg(assumption_obj), '[]'::jsonb)
  INTO v_assumptions
  FROM (
    SELECT jsonb_build_object(
      'assumption_id', ba.id,
      'selected_claim_id', ba.selected_claim_id,
      'conflict_id', ba.conflict_id,
      'scope', ba.scope,
      'ttl_utc', ba.ttl_utc,
      'rationale', ba.rationale,
      'created_by', ba.created_by,
      'created_at_utc', ba.created_at_utc
    ) AS assumption_obj
    FROM belief_assumptions ba
    JOIN belief_claims bc ON ba.selected_claim_id = bc.id
    WHERE bc.project_id = p_project_id
      AND ba.ttl_utc > NOW()
    ORDER BY ba.created_at_utc DESC
    LIMIT 5
  ) ranked_assumptions;

  -- Open loops: overdue first, then by due_date
  SELECT COALESCE(jsonb_agg(loop_obj), '[]'::jsonb)
  INTO v_open_loops
  FROM (
    SELECT jsonb_build_object(
      'loop_id', ol.id,
      'owner_entity_id', ol.owner_entity_id,
      'due_date', ol.due_date,
      'status', ol.status::text,
      'summary', ol.summary,
      'event_at_utc', ol.event_at_utc,
      'pointers', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'source_type', lp.source_type::text,
          'source_id', lp.source_id,
          'ts_start', lp.ts_start,
          'ts_end', lp.ts_end
        ))
        FROM loop_pointers lp
        WHERE lp.loop_id = ol.id
      ), '[]'::jsonb)
    ) AS loop_obj
    FROM belief_open_loops ol
    WHERE ol.project_id = p_project_id
      AND ol.status IN ('open', 'overdue')
    ORDER BY 
      CASE ol.status WHEN 'overdue' THEN 0 ELSE 1 END,
      ol.due_date NULLS LAST
    LIMIT 10
  ) ranked_loops;

  -- Assemble final result
  v_result := jsonb_build_object(
    'project_id', p_project_id,
    'snapshot_generated_at_utc', NOW(),
    'policy_version', 'v1.0.0',
    'limits', v_limits,
    'coverage', v_coverage,
    'claims', v_claims,
    'conflicts', v_conflicts,
    'assumptions', v_assumptions,
    'open_loops', v_open_loops
  );

  RETURN v_result;
END;
$$;

-- Debug view
CREATE OR REPLACE VIEW v_project_belief_snapshot AS
SELECT 
  p.id AS project_id,
  p.name AS project_name,
  get_project_belief_snapshot(p.id) AS snapshot
FROM projects p;

COMMENT ON FUNCTION get_project_belief_snapshot(UUID) IS 
'G2.1: Returns belief snapshot for M7 memory injection per interface v1.1';
;
