
-- Mark placeholder phone contacts as inactive/archived via notes
-- Don't delete - preserve for audit trail, but flag as incomplete data
UPDATE contacts 
SET notes = COALESCE(notes, '') || ' | INACTIVE: Placeholder phone - no real contact info available, 0 interactions'
WHERE phone LIKE '+1000000000%' OR phone = 'UNKNOWN';
;
