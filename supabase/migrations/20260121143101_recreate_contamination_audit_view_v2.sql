
-- Recreate v_contamination_audit view
DROP VIEW IF EXISTS v_contamination_audit;

CREATE VIEW v_contamination_audit AS
WITH call_context AS (
  SELECT 
    i.interaction_id,
    i.project_id AS attributed_project_id,
    p.name AS attributed_project,
    i.contact_id,
    i.contact_phone,
    (cr.raw_snapshot_json->'signal'->>'transcript') AS transcript,
    i.event_at_utc
  FROM interactions i
  JOIN projects p ON i.project_id = p.id
  LEFT JOIN calls_raw cr ON i.interaction_id = cr.interaction_id
  WHERE i.channel = 'call'
    AND i.contact_id IS NULL
    AND i.project_id IS NOT NULL
)
SELECT 
  interaction_id,
  attributed_project,
  event_at_utc,
  (SELECT COUNT(DISTINCT s.project_id)
   FROM scan_transcript_for_projects(cc.transcript, 0.5) s
   WHERE s.project_id <> cc.attributed_project_id
     AND s.matched_alias <> 'sittler'
  )::INT AS cross_project_mentions,
  (SELECT STRING_AGG(DISTINCT s.project_name || ' (' || s.matched_term || ')', ', ')
   FROM scan_transcript_for_projects(cc.transcript, 0.5) s
   WHERE s.project_id <> cc.attributed_project_id
     AND s.matched_alias <> 'sittler'
  ) AS cross_mentions_detail,
  (SELECT COUNT(*)
   FROM journal_claims jc
   JOIN journal_runs jr ON jc.run_id = jr.run_id
   WHERE jr.call_id = cc.interaction_id
  ) AS claim_count
FROM call_context cc
WHERE transcript IS NOT NULL;
;
