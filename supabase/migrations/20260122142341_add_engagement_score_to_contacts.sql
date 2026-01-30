-- Add engagement_score with weighted formula
-- Weights: 
--   transcript depth (chars/1000) as primary signal
--   vendor multiplier (2x for subcontractor/supplier)
--   key contact boost (+1000 baseline)

ALTER TABLE contacts ADD COLUMN IF NOT EXISTS engagement_score numeric;

-- Compute initial scores
UPDATE contacts
SET engagement_score = (
  -- Base: transcript depth (chars / 1000)
  COALESCE(total_transcript_chars, 0) / 1000.0
  
  -- Vendor multiplier: 2x for revenue-generating contacts
  * CASE WHEN contact_type IN ('subcontractor', 'supplier') THEN 2.0 ELSE 1.0 END
  
  -- Key contact boost: +500 baseline for critical people (TNF, HCB staff)
  + CASE WHEN is_key_contact = true THEN 500 ELSE 0 END
  
  -- Recency bonus: +50 if contacted in last 7 days
  + CASE WHEN last_interaction_at > NOW() - INTERVAL '7 days' THEN 50 ELSE 0 END
);

-- Add comment explaining the score
COMMENT ON COLUMN contacts.engagement_score IS 
  'Weighted engagement: (transcript_chars/1000) * vendor_mult(2x) + key_contact_boost(500) + recency_bonus(50). Higher = more significant.';;
