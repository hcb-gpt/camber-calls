-- GT Ingestion Receipt Function
-- Returns a receipt after inserting GT segment data

CREATE OR REPLACE FUNCTION ingest_gt_segment(
  p_call_id TEXT,
  p_batch_id TEXT,
  p_segment_index INTEGER,
  p_turn_type TEXT,
  p_thread_before TEXT DEFAULT NULL,
  p_thread_after TEXT DEFAULT NULL,
  p_project_name TEXT DEFAULT NULL,
  p_line_start INTEGER DEFAULT NULL,
  p_line_end INTEGER DEFAULT NULL,
  p_evidence_span TEXT DEFAULT NULL,
  p_confidence TEXT DEFAULT 'MEDIUM',
  p_labeler TEXT DEFAULT 'CHAD',
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_id UUID;
  v_project_id UUID;
BEGIN
  -- Resolve project_id if project_name provided
  IF p_project_name IS NOT NULL THEN
    SELECT id INTO v_project_id 
    FROM projects 
    WHERE name ILIKE p_project_name
    LIMIT 1;
  END IF;
  
  -- Insert segment
  INSERT INTO ground_truth_segments (
    call_id, batch_id, segment_index, turn_type,
    thread_before, thread_after, project_id, project_name,
    line_start, line_end, evidence_span,
    confidence, labeler, notes
  ) VALUES (
    p_call_id, p_batch_id, p_segment_index, p_turn_type,
    p_thread_before, p_thread_after, v_project_id, p_project_name,
    p_line_start, p_line_end, p_evidence_span,
    p_confidence, p_labeler, p_notes
  )
  ON CONFLICT (call_id, segment_index, turn_type) 
  DO UPDATE SET
    thread_before = EXCLUDED.thread_before,
    thread_after = EXCLUDED.thread_after,
    project_id = EXCLUDED.project_id,
    project_name = EXCLUDED.project_name,
    line_start = EXCLUDED.line_start,
    line_end = EXCLUDED.line_end,
    evidence_span = EXCLUDED.evidence_span,
    confidence = EXCLUDED.confidence,
    labeler = EXCLUDED.labeler,
    notes = EXCLUDED.notes,
    label_date = now()
  RETURNING id INTO v_id;
  
  -- Return receipt
  RETURN jsonb_build_object(
    'receipt_type', 'GT_SEGMENT_INGESTION',
    'receipt_version', '1.0.0',
    'segment_id', v_id,
    'call_id', p_call_id,
    'batch_id', p_batch_id,
    'segment_index', p_segment_index,
    'turn_type', p_turn_type,
    'project_resolved', v_project_id IS NOT NULL,
    'ingested_at', now()
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ingest_gt_segment IS 
'Ingests a single GT segment and returns a receipt. Upserts on (call_id, segment_index, turn_type).';;
