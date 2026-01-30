
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
  v_adapters JSONB;
  v_calls_processed JSONB;
  v_known_gaps TEXT[];
  v_char_count INT;
  v_max_chars INT := 6000;
  v_max_claims INT := 20;
  v_max_conflicts INT := 5;
  v_max_open_loops INT := 10;
  v_max_assumptions INT := 5;
BEGIN
  -- ==========================================
  -- 1. COVERAGE BLOCK (mandatory, never truncated)
  -- ==========================================
  
  -- Calls processed stats
  SELECT jsonb_build_object(
    'range_start_utc', MIN(event_at_utc),
    'range_end_utc', MAX(event_at_utc),
    'count', COUNT(*),
    'ingestion_lag_hours', ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(ingested_at_utc))) / 3600.0, 2)
  )
  INTO v_calls_processed
  FROM interactions
  WHERE project_id = p_project_id
    AND channel = 'call';
  
  -- Handle null case
  IF v_calls_processed IS NULL OR v_calls_processed->>'count' IS NULL THEN
    v_calls_processed := jsonb_build_object(
      'range_start_utc', NULL,
      'range_end_utc', NULL,
      'count', 0,
      'ingestion_lag_hours', NULL
    );
  END IF;
  
  -- Adapter status
  SELECT jsonb_object_agg(
    adapter_name,
    jsonb_build_object(
      'status', status,
      'last_sync_utc', last_sync_utc
    )
  )
  INTO v_adapters
  FROM adapter_status;
  
  IF v_adapters IS NULL THEN
    v_adapters := '{}'::JSONB;
  END IF;
  
  -- Known gaps
  v_known_gaps := ARRAY[]::TEXT[];
  
  -- Check for missing integrations
  IF NOT EXISTS (SELECT 1 FROM adapter_status WHERE adapter_name = 'buildertrend' AND status = 'active') THEN
    v_known_gaps := array_append(v_known_gaps, 'BuilderTrend finance not yet integrated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM adapter_status WHERE adapter_name = 'email' AND status = 'active') THEN
    v_known_gaps := array_append(v_known_gaps, 'Email adapter not built');
  END IF;
  
  -- Build coverage object
  v_coverage := jsonb_build_object(
    'calls_processed', v_calls_processed,
    'adapters', v_adapters,
    'entity_resolution', jsonb_build_object(
      'projects_searched', jsonb_build_array(p_project_id),
      'confidence', 1.0
    ),
    'known_gaps', to_jsonb(v_known_gaps)
  );
  
  -- ==========================================
  -- 2. CLAIMS (with truncation by relevance)
  -- ==========================================
  
  SELECT COALESCE(jsonb_agg(claim_obj ORDER BY relevance_score DESC), '[]'::JSONB)
  INTO v_claims
  FROM (
    SELECT 
      jsonb_build_object(
        'claim_id', bc.id,
        'claim_type', bc.claim_type,
        'epistemic_status', bc.epistemic_status,
        'warrant_level', bc.warrant_level,
        'confidence', bc.confidence,
        'confidence_rationale', bc.confidence_rationale,
        'lifecycle', bc.lifecycle,
        'subject_refs', jsonb_build_object(
          'project_id', bc.project_id,
          'contact_id', bc.contact_id,
          'vendor_id', bc.vendor_id
        ),
        'speaker_entity_id', bc.speaker_entity_id,
        'origin_entity_id', bc.origin_entity_id,
        'origin_kind', bc.origin_kind,
        'origin_confidence', bc.origin_confidence,
        'event_at_utc', bc.event_at_utc,
        'ingested_at_utc', bc.ingested_at_utc,
        'pointers', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
            'source_type', cp.source_type,
            'source_id', cp.source_id,
            'ts_start', cp.ts_start,
            'ts_end', cp.ts_end
          ))
          FROM claim_pointers cp
          WHERE cp.claim_id = bc.id
        ), '[]'::JSONB),
        'short_text', bc.short_text
      ) as claim_obj,
      -- Relevance score: recency × confidence × warrant_level weight × lifecycle weight
      (
        EXTRACT(EPOCH FROM bc.event_at_utc) / 1000000000.0 * 
        bc.confidence * 
        CASE bc.warrant_level 
          WHEN 'execution_accept' THEN 1.5 
          ELSE 1.0 
        END *
        CASE bc.lifecycle
          WHEN 'active' THEN 1.0
          WHEN 'disputed' THEN 0.8
          ELSE 0.3
        END
      ) as relevance_score
    FROM belief_claims bc
    WHERE bc.project_id = p_project_id
      AND bc.lifecycle IN ('active', 'disputed')
    ORDER BY relevance_score DESC
    LIMIT v_max_claims
  ) ranked_claims;
  
  -- ==========================================
  -- 3. CONFLICTS (oldest unresolved first)
  -- ==========================================
  
  SELECT COALESCE(jsonb_agg(conflict_obj), '[]'::JSONB)
  INTO v_conflicts
  FROM (
    SELECT jsonb_build_object(
      'conflict_id', bf.id,
      'claim_ids', (
        SELECT jsonb_agg(cc.claim_id)
        FROM conflict_claims cc
        WHERE cc.conflict_id = bf.id
      ),
      'conflict_type', bf.conflict_type,
      'status', bf.status,
      'summary', bf.summary
    ) as conflict_obj
    FROM belief_conflicts bf
    WHERE bf.status = 'unresolved'
      AND EXISTS (
        SELECT 1 FROM conflict_claims cc
        JOIN belief_claims bc ON cc.claim_id = bc.id
        WHERE cc.conflict_id = bf.id AND bc.project_id = p_project_id
      )
    ORDER BY bf.created_at ASC
    LIMIT v_max_conflicts
  ) ranked_conflicts;
  
  -- ==========================================
  -- 4. ASSUMPTIONS (most recent first)
  -- ==========================================
  
  SELECT COALESCE(jsonb_agg(assumption_obj), '[]'::JSONB)
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
    ) as assumption_obj
    FROM belief_assumptions ba
    JOIN belief_claims bc ON ba.selected_claim_id = bc.id
    WHERE bc.project_id = p_project_id
      AND ba.ttl_utc > NOW()  -- Only active assumptions
    ORDER BY ba.created_at_utc DESC
    LIMIT v_max_assumptions
  ) ranked_assumptions;
  
  -- ==========================================
  -- 5. OPEN LOOPS (overdue first, then by due_date)
  -- ==========================================
  
  SELECT COALESCE(jsonb_agg(loop_obj), '[]'::JSONB)
  INTO v_open_loops
  FROM (
    SELECT jsonb_build_object(
      'loop_id', ol.id,
      'owner_entity_id', ol.owner_entity_id,
      'due_date', ol.due_date,
      'status', ol.status,
      'summary', ol.summary,
      'event_at_utc', ol.event_at_utc,
      'pointers', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'source_type', lp.source_type,
          'source_id', lp.source_id,
          'ts_start', lp.ts_start,
          'ts_end', lp.ts_end
        ))
        FROM loop_pointers lp
        WHERE lp.loop_id = ol.id
      ), '[]'::JSONB)
    ) as loop_obj
    FROM belief_open_loops ol
    WHERE ol.project_id = p_project_id
      AND ol.status IN ('open', 'overdue')
    ORDER BY 
      CASE ol.status WHEN 'overdue' THEN 0 ELSE 1 END,
      ol.due_date ASC NULLS LAST
    LIMIT v_max_open_loops
  ) ranked_loops;
  
  -- ==========================================
  -- 6. ASSEMBLE FINAL RESULT
  -- ==========================================
  
  v_result := jsonb_build_object(
    'project_id', p_project_id,
    'snapshot_generated_at_utc', NOW(),
    'policy_version', 'v1.0.0',
    'limits', jsonb_build_object(
      'max_chars', v_max_chars,
      'max_claims', v_max_claims,
      'max_conflicts', v_max_conflicts,
      'max_open_loops', v_max_open_loops,
      'max_assumptions', v_max_assumptions
    ),
    'coverage', v_coverage,
    'claims', v_claims,
    'conflicts', v_conflicts,
    'assumptions', v_assumptions,
    'open_loops', v_open_loops
  );
  
  -- ==========================================
  -- 7. SIZE ENFORCEMENT (truncate claims if needed)
  -- ==========================================
  
  v_char_count := length(v_result::TEXT);
  
  -- If over limit, progressively remove lowest-relevance claims
  WHILE v_char_count > v_max_chars AND jsonb_array_length(v_result->'claims') > 0 LOOP
    v_result := jsonb_set(
      v_result,
      '{claims}',
      (v_result->'claims') - (jsonb_array_length(v_result->'claims') - 1)
    );
    v_char_count := length(v_result::TEXT);
  END LOOP;
  
  RETURN v_result;
END;
$$;

-- ==========================================
-- Debug view: v_project_belief_snapshot
-- ==========================================

CREATE OR REPLACE VIEW v_project_belief_snapshot AS
SELECT 
  p.id as project_id,
  p.name as project_name,
  get_project_belief_snapshot(p.id) as snapshot
FROM projects p;

-- Grant execute
GRANT EXECUTE ON FUNCTION get_project_belief_snapshot(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_project_belief_snapshot(UUID) TO service_role;
;
