-- Fix dashboard view to use GREEN/YELLOW/RED
CREATE OR REPLACE VIEW entity_drift_dashboard AS
SELECT 
  field_name,
  unique_count,
  alert_threshold,
  critical_threshold,
  status,
  CASE 
    WHEN status = 'GREEN' THEN 100
    WHEN status = 'YELLOW' THEN 50
    WHEN status = 'RED' THEN 0
  END AS health_score
FROM (
  SELECT 
    'contacts.role' AS field_name,
    COUNT(DISTINCT role) AS unique_count,
    120 AS alert_threshold,
    150 AS critical_threshold,
    CASE 
      WHEN COUNT(DISTINCT role) > 150 THEN 'RED'
      WHEN COUNT(DISTINCT role) > 120 THEN 'YELLOW'
      ELSE 'GREEN'
    END AS status
  FROM contacts WHERE role IS NOT NULL
  
  UNION ALL
  
  SELECT 
    'contacts.trade',
    COUNT(DISTINCT trade),
    80,
    100,
    CASE 
      WHEN COUNT(DISTINCT trade) > 100 THEN 'RED'
      WHEN COUNT(DISTINCT trade) > 80 THEN 'YELLOW'
      ELSE 'GREEN'
    END
  FROM contacts WHERE trade IS NOT NULL
  
  UNION ALL
  
  SELECT 
    'interactions.review_reasons',
    COUNT(DISTINCT reason_val),
    500,
    600,
    CASE 
      WHEN COUNT(DISTINCT reason_val) > 600 THEN 'RED'
      WHEN COUNT(DISTINCT reason_val) > 500 THEN 'YELLOW'
      ELSE 'GREEN'
    END
  FROM (SELECT unnest(review_reasons) AS reason_val FROM interactions WHERE review_reasons IS NOT NULL) r
) combined;;
