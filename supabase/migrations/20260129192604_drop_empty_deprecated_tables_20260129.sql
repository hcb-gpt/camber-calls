-- Drop empty deprecated tables (n8n and raycast integrations)
-- All have 0 rows and appear to be unused

DROP TABLE IF EXISTS n8n_shadow_runs;
DROP TABLE IF EXISTS n8n_shadow_errors;
DROP TABLE IF EXISTS raycast_clients;
DROP TABLE IF EXISTS raycast_cost_codes;;
