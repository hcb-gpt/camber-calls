-- Frozen baseline per STRAT directive 2026-01-30
-- Do not modify during v3.8 validation period

CREATE OR REPLACE VIEW baseline_v3_calls_success AS
SELECT DISTINCT interaction_id
FROM interactions
WHERE channel = 'call'
  AND interaction_id NOT LIKE 'cll_V38%'
  AND interaction_id NOT LIKE 'cll_TEST%'
  AND interaction_id NOT LIKE 'cll_SHADOW%'
  AND interaction_id NOT LIKE 'cll_STABILITY%'
  AND interaction_id LIKE 'cll_%';

COMMENT ON VIEW baseline_v3_calls_success IS 'FROZEN 2026-01-30. v3 baseline for v3.8 validation. Do not modify until validation complete.';;
