-- View to audit calls at risk of wrong-project attribution
CREATE OR REPLACE VIEW v_contamination_audit AS
WITH call_context AS (
  SELECT 
    i.interaction_id,
    i.project_id as attributed_project_id,
    p.name as attributed_project,
    i.contact_id,
    i.contact_phone,
    cr.raw_snapshot_json->'signal'->>'transcript' as transcript,
    cr.raw_snapshot_json->'metadata'->'context_assembly_receipt'->>'sources_used' as sources_used,
    i.event_at_utc
  FROM interactions i
  JOIN projects p ON i.project_id = p.id
  LEFT JOIN calls_raw cr ON i.interaction_id = cr.interaction_id
  WHERE i.channel = 'call'
    AND i.contact_id IS NULL  -- Contact resolution failed
    AND i.project_id IS NOT NULL  -- But project was assigned (via fallback)
)
SELECT 
  cc.interaction_id,
  cc.attributed_project,
  cc.event_at_utc,
  ARRAY_LENGTH(
    (SELECT ARRAY_AGG(DISTINCT s.project_id) 
     FROM scan_transcript_for_projects(cc.transcript, 0.5) s
     WHERE s.project_id != cc.attributed_project_id
       AND s.match_type IN ('exact', 'prefix')
       AND s.matched_alias NOT IN ('sittler')), 1
  ) as cross_project_mentions,
  (SELECT STRING_AGG(DISTINCT s.project_name || ' (' || s.matched_term || ')', ', ')
   FROM scan_transcript_for_projects(cc.transcript, 0.5) s
   WHERE s.project_id != cc.attributed_project_id
     AND s.match_type IN ('exact', 'prefix')
     AND s.matched_alias NOT IN ('sittler')
  ) as cross_mentions_detail,
  (SELECT COUNT(*) FROM journal_claims jc
   JOIN journal_runs jr ON jc.run_id = jr.run_id
   WHERE jr.call_id = cc.interaction_id) as claim_count
FROM call_context cc
WHERE cc.transcript IS NOT NULL;

COMMENT ON VIEW v_contamination_audit IS 
'Audits calls at risk of wrong-project attribution. Shows calls with NULL contact_id that mention projects other than their attributed project.';;
