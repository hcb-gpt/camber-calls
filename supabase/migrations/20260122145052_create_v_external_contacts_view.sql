
-- External contacts view for prioritization
-- Excludes HCB and TNF (internal staff)
CREATE VIEW v_external_contacts AS
SELECT 
  id,
  name,
  company,
  role,
  phone,
  email,
  interaction_count,
  last_interaction_at,
  total_transcript_chars,
  engagement_score,
  is_key_contact,
  key_contact_reason
FROM contacts
WHERE is_internal = FALSE
  AND interaction_count > 0
ORDER BY 
  COALESCE(engagement_score, interaction_count) DESC;
;
