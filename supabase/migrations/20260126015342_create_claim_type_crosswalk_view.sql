-- Claim Type Crosswalk: journal_claims → belief_claims alignment
-- Per STRAT-21 R&D crosswalk v0.3.8

CREATE OR REPLACE VIEW claim_type_crosswalk AS
SELECT * FROM (VALUES
  -- journal_claims.claim_type → belief_claims.claim_type_enum → status
  ('update',      'state',       'ALIGNED'),
  ('fact',        'state',       'ALIGNED'),
  ('decision',    'decision',    'EXACT'),
  ('commitment',  'commitment',  'EXACT'),
  ('requirement', 'request',     'ALIAS'),   -- requirement → request
  ('concern',     'risk',        'ALIAS'),   -- concern → risk  
  ('blocker',     'open_loop',   'ALIAS'),   -- blocker → open_loop
  ('deadline',    'event',       'ALIAS'),   -- deadline is a time-bound event
  ('question',    'open_loop',   'ALIAS'),   -- question creates open loop
  ('preference',  'state',       'ALIAS')    -- preference is a stated state
) AS t(journal_type, belief_type, alignment_status);

COMMENT ON VIEW claim_type_crosswalk IS 
'Maps journal_claims.claim_type (text) to belief_claims.claim_type_enum. 
EXACT = same label, ALIAS = semantic equivalent, ALIGNED = category match.
Per STRAT-21 crosswalk v0.3.8.';;
